/** @format */

import { CONGRESS_LOCALE_NAME, Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isAtLargeLegislator, isCongressLocale } from "@sway/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { get } from "lodash";
import { fire, sway } from "sway";
import { db, firestore } from "../firebase";
import { isEmptyObject } from "../utils";

const { logger } = functions;

interface IData extends Partial<sway.IBill> {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}

export const getLegislatorUserScores = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<sway.IAggregatedBillLocaleScores> => {
        if (!context.auth?.uid) {
            logger.error("Unauthed request to getLegislatorUserScores");
            return defaultReturn(data.legislator.externalId);
        }

        const { locale, legislator } = data;
        const fireClient = new SwayFireClient(db, locale, firestore, logger);

        logger.info(
            `Starting getLegislatorUserScores for locale and legislator - ${locale.name} - ${legislator.externalId}/${legislator.district}`,
        );

        const _isAtLargeLegislator = () => {
            return isAtLargeLegislator(legislator) || locale.name === CONGRESS_LOCALE_NAME;
        };

        const getUsersCountInLocale = async (): Promise<sway.IBillLocaleUserCount | undefined> => {
            logger.info("getUsersCountInLocale for locale -", locale.name);
            const data_ = await fireClient.locales().get(locale);
            if (!data_?.userCount) return;

            return {
                countAllUsersInLocale: Number(data_.userCount.all || 0),
                countAllUsersInDistrict: (() => {
                    if (_isAtLargeLegislator()) {
                        if (isCongressLocale(locale)) {
                            return (
                                Number(data_.userCount[legislator.regionCode.toUpperCase()]) || 0
                            );
                        } else {
                            return Number(data_.userCount.all || 0);
                        }
                    } else {
                        return Number(data_.userCount[legislator.district] || 0);
                    }
                })(),
            };
        };

        const getLegislatorVote = async (
            billFirestoreId: string,
        ): Promise<sway.ILegislatorVote | undefined> => {
            logger.info("getLegislatorVote for billFirestoreId -", billFirestoreId);
            return fireClient.legislatorVotes().get(legislator.externalId, billFirestoreId);
        };

        const getBillIds = async (): Promise<string[]> => {
            logger.info("getting active billIds for locale - ", locale.name);
            const docs1: fire.TypedQuerySnapshot<sway.IBill> | void = await fireClient
                .bills()
                .where("active", "==", true)
                .get()
                .catch(console.error);

            const ids: string[] | void = docs1 && docs1.docs.map((d) => d.id);

            if (!ids || isEmptyObject(ids)) return [];

            return [...new Set(ids)];
        };

        const getBillScores = async (billFirestoreId: string) => {
            const scores = await fireClient.billScores().get(billFirestoreId);
            logger.info(
                `getBillScores for billFirestoreId - ${billFirestoreId}`,
                JSON.stringify(scores, null, 4),
            );
            if (!scores) return;

            const districtFor = get(scores, `districts.${legislator.district}.for`);
            const districtAgainst = get(scores, `districts.${legislator.district}.against`);

            return {
                all: {
                    for: scores.for,
                    against: scores.against,
                },
                district: {
                    for: _isAtLargeLegislator() ? scores.for : districtFor,
                    against: _isAtLargeLegislator() ? scores.against : districtAgainst,
                },
            };
        };

        const getAllBillScoreCounts = async (): Promise<
            sway.IAggregatedBillLocaleScores | undefined
        > => {
            logger.info("getAllBillScoreCounts - getting billIds and userCount for locale");
            const [billIds, userCount] = await Promise.all([getBillIds(), getUsersCountInLocale()]);
            logger.info("updating bill scores for billIds and userCount - ", billIds, userCount);
            if (!userCount || userCount?.countAllUsersInLocale === undefined) {
                logger.error("no users in locale -", locale.name);
                return;
            }

            const billScores = billIds.map(
                async (id: string): Promise<sway.IBillLocaleScore | undefined> => {
                    const [legislatorVote, billScore] = await Promise.all([
                        getLegislatorVote(id),
                        getBillScores(id),
                    ]);
                    logger.info(
                        `billScore and legislator vote for billFirestoreId - ${id}`,
                        JSON.stringify(billScore, null, 4),
                        JSON.stringify(legislatorVote, null, 4),
                    );
                    if (!legislatorVote) return;
                    if (!billScore) return;
                    if (legislatorVote.support === Support.Abstain) return;

                    const support = legislatorVote.support;

                    const agreedAll = get(billScore, `all.${support}`) || 0;
                    const disagreedAll = Number(
                        support !== Support.For ? billScore.all.for : billScore.all.against,
                    );

                    const agreedDistrict = get(billScore, `district.${support}`) || 0;
                    const disagreedDistrict =
                        support !== Support.For
                            ? billScore.district.for
                            : billScore.district.against;

                    return {
                        billFirestoreId: id,
                        agreedDistrict: _isAtLargeLegislator() ? agreedAll : agreedDistrict,
                        disagreedDistrict: _isAtLargeLegislator()
                            ? disagreedAll
                            : disagreedDistrict,
                        agreedAll: agreedAll,
                        disagreedAll: disagreedAll,
                    };
                },
            );

            const _billScores = (await Promise.all(billScores)).filter(
                Boolean,
            ) as sway.IBillLocaleScore[];
            logger.info(
                "Reducing billScores to totals. Bill Scores -",
                JSON.stringify(_billScores, null, 4),
            );

            const totals = _billScores.reduce(
                (sum: sway.ITotalBillLocaleScores, billScore: any) => {
                    if (!billScore) return sum;

                    sum.billFirestoreIds = sum.billFirestoreIds.concat(billScore.billFirestoreId);
                    sum.totalAgreedDistrict += billScore.agreedDistrict;
                    sum.totalDisagreedDistrict += billScore.disagreedDistrict;
                    sum.totalAgreedAll += billScore.agreedAll;
                    sum.totalDisagreedAll += billScore.disagreedAll;
                    return sum;
                },
                {
                    billFirestoreIds: [],
                    totalAgreedDistrict: 0,
                    totalDisagreedDistrict: 0,
                    totalAgreedAll: 0,
                    totalDisagreedAll: 0,
                },
            );

            logger.info("Reduced total scores -", totals);
            return {
                externalLegislatorId: legislator.externalId,
                ...userCount,
                ...totals,
                billScores: _billScores,
            };
        };

        const finalScores: sway.IAggregatedBillLocaleScores | undefined =
            await getAllBillScoreCounts();
        if (!finalScores) {
            return defaultReturn(legislator.externalId);
        }

        const stringified = JSON.stringify(finalScores, null, 4);
        logger.info("Returning score data from function", typeof finalScores, stringified);
        return finalScores;
    },
);

const defaultReturn = (externalLegislatorId: string): sway.IAggregatedBillLocaleScores => ({
    externalLegislatorId: externalLegislatorId,
    countAllUsersInLocale: 0,
    countAllUsersInDistrict: 0,
    billFirestoreIds: [],
    totalAgreedDistrict: 0,
    totalDisagreedDistrict: 0,
    totalAgreedAll: 0,
    totalDisagreedAll: 0,
    billScores: [],
});
