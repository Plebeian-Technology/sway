/** @format */

import {
    Collections,
    CONGRESS_LOCALE_NAME,
    STATE_NAMES_CODES,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
import { db, firestore } from "../firebase";

const { logger } = functions;

export const onInsertUserVoteUpdateScore = functions.firestore
    .document(`${Collections.UserVotes}/{locale}/{uid}/{billFirestoreId}`)
    .onCreate(
        async (snapshot: QueryDocumentSnapshot, context: EventContext) => {
            logger.info("user vote created, running score update function");

            const doc: sway.IUserVote = snapshot.data() as sway.IUserVote;
            if (!doc) {
                logger.error("no user vote");
                return false;
            }

            const { support } = doc;
            if (!support) {
                logger.error("user vote is missing support");
                return false;
            }

            const billFirestoreId = snapshot.ref.id;
            const uid = snapshot.ref.parent.id;
            const localeName = snapshot.ref.parent.parent?.id;

            logger.info("user vote create update function");
            logger.info(`billFirestoreId - ${billFirestoreId}`);
            logger.info(`uid - ${uid}`);
            logger.info(`localeName - ${localeName}`);

            const swayFire = new SwayFireClient(
                db,
                { name: localeName } as sway.ILocale,
                firestore,
            );
            const bill = await swayFire.bills().get(billFirestoreId);
            if (!bill) {
                logger.error(
                    `no bill found with billFirestoreId - ${billFirestoreId} - in locale - ${localeName}. Skipping user vote score updates.`,
                );
                return false;
            }

            const userAdminSettings = (await swayFire
                .users(uid)
                .get()) as sway.IUserWithSettingsAdmin;
            if (!userAdminSettings) {
                logger.error("could not find user");
                return false;
            }
            const user = userAdminSettings.user;
            if (
                localeName !== CONGRESS_LOCALE_NAME &&
                user?.locale?.name !== localeName
            ) {
                logger.error("user locale !== bill locale");
                logger.error(`user locale - ${user?.locale?.name}`);
                logger.error(`bill locale - ${localeName}`);
                return false;
            }
            if (typeof user.locale?.district !== "number") {
                logger.error(
                    "user district was not a number - received",
                    user.locale?.district,
                );
                logger.error("skipping get user representatives");
                return false;
            }

            const district =
                localeName === CONGRESS_LOCALE_NAME
                    ? user.locale.congressionalDistrict
                    : user.locale.district;
            if (!district) {
                logger.error("NO DISTRICT");
                return;
            }
            const _regionCode = user.locale._regionCode || user.locale._region;
            const regionCode =
                _regionCode.length > 2 // @ts-ignore
                    ? STATE_NAMES_CODES[_regionCode] // @ts-ignore
                        ? STATE_NAMES_CODES[_regionCode]
                        : _regionCode
                    : _regionCode;

            const representatives = await swayFire
                .legislators()
                .representatives(uid, district, regionCode, bill.active);
            if (!representatives || representatives.length === 0) {
                logger.error(`no representatives found for user - ${uid}`);
                return false;
            }

            representatives.forEach(
                async (
                    legislator: sway.ILegislatorWithUserScore | undefined,
                ) => {
                    if (!legislator) {
                        logger.error(
                            `representative is undefined on bill ${billFirestoreId}`,
                        );
                        return;
                    }

                    const legislatorVote: sway.ILegislatorVote | void = await swayFire
                        .legislatorVotes()
                        .get(legislator.legislator.externalId, billFirestoreId);
                    if (!legislatorVote) {
                        logger.warn(
                            "legislatorVote is falsey, proceeding with userLegislatorVotes update/create",
                        );
                    }

                    const userLegislatorVoteRef: fire.TypedDocumentReference<sway.IUserLegislatorVote> | void = await swayFire
                        .userLegislatorVotes(uid)
                        .create(
                            support,
                            legislatorVote && legislatorVote.support,
                            billFirestoreId,
                            legislator.legislator.externalId,
                        );
                    if (!userLegislatorVoteRef) {
                        logger.error(
                            `skipping update of legislator scores because, could not create user/legislator vote for user - ${uid}. returns undefined when updating existing doc and legislatorVote is falsey`,
                        );
                        return;
                    }

                    logger.info("updating user/legislator score on bill");
                    logger.info(`user: ${uid}`);
                    logger.info(`bill: ${billFirestoreId}`);
                    logger.info(
                        `legislator: ${legislator.legislator.externalId}`,
                    );
                    swayFire
                        .userLegislatorScores()
                        .update(
                            legislator.legislator,
                            legislatorVote,
                            doc,
                            userLegislatorVoteRef.path,
                            uid,
                        );
                    swayFire
                        .userDistrictScores()
                        .update(
                            legislator.legislator,
                            legislatorVote,
                            doc,
                            userLegislatorVoteRef.path,
                        );
                },
            );

            const path = snapshot.ref.path;
            const now = firestore.FieldValue.serverTimestamp();

            logger.info("user vote insert - update bill scores");
            await swayFire.billScores().update(billFirestoreId, support);

            if (user.locale?.district) {
                logger.info(
                    "updating district score for district -",
                    user.locale.district,
                );
                await swayFire
                    .billScores()
                    .updateDistrictScores(
                        billFirestoreId,
                        support,
                        user.locale.district,
                    );
            }

            logger.info("updating district score for district - 0");
            await swayFire
                .billScores()
                .updateDistrictScores(billFirestoreId, support, 0);

            logger.info("update bill with new user vote path");
            await swayFire.bills().update(doc, {
                updatedAt: now,
                userVotePaths: firestore.FieldValue.arrayUnion(path),
            });

            return true;
        },
    );
