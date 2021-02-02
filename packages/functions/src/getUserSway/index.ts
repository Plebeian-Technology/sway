/** @format */

import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db, firestore } from "../firebase";

const { logger } = functions;

interface IData extends Partial<sway.IBill> {
    uid: string;
    locale: sway.IUserLocale;
}

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

interface ICountShares {
    countBillsShared: number;
    countAllBillShares: number;
    countFacebookShares: number;
    countTwitterShares: number;
    countTelegramShares: number;
    countWhatsappShares: number;
    uids: string[];
}

// onRequest for external connections like Express (req/res)
export const getUserSway = functions.https.onCall(
    async (
        data: IData,
        context: CallableContext,
    ): Promise<IResponseData | undefined> => {
        if (context?.auth?.uid !== data?.uid) {
            logger.error(
                "auth uid does not match data uid, skipping user sway aggregation",
            );
            return;
        }
        logger.info("getting user sway");
        const { locale } = data;
        if (!data.uid) {
            logger.error(
                "did not receive a data.uid, skipping user sway aggregation",
            );
            return;
        }
        if (!locale) {
            logger.error(
                "did not receive a locale, skipping user sway aggregation",
            );
            return;
        }

        const fireClient = new SwayFireClient(db, locale, firestore);

        const countUserVotesByLocale = async (uid: string | "total") => {
            return (await fireClient.userVotes(uid).list()).length;
        };
        const countUserInvites = async (uid: string | "total") => {
            const invites = await fireClient.userInvites(uid).get();
            if (!invites) return 0;

            return invites.emails.length;
        };

        const initialShares: ICountShares = {
            countBillsShared: 0, // if a user has shared a bill in any way
            countAllBillShares: 0, // total number of ways in which a user has shared a bill
            countFacebookShares: 0,
            countTwitterShares: 0,
            countTelegramShares: 0,
            countWhatsappShares: 0,
            uids: [],
        };

        const increment = (sum: number, inc: number | undefined) => {
            if (!inc) return sum;
            return sum + inc;
        };

        const countShares = async (
            uid: string | "total",
        ): Promise<ICountShares> => {
            const shares = await fireClient.userBillShares(uid).list();
            return shares.reduce(
                (sum: ICountShares, share: sway.IUserBillShare) => {
                    const billShares = Object.values(share.platforms).filter(Boolean);
                    const isSharedBill = billShares.length > 0;
                    const {
                        uids,
                        platforms: { facebook, twitter, whatsapp, telegram },
                    } = share;
                    sum = {
                        countAllBillShares:
                            sum.countBillsShared + billShares.length,
                        countBillsShared:
                            sum.countBillsShared + Number(isSharedBill),
                        countFacebookShares: increment(
                            sum.countFacebookShares,
                            facebook,
                        ),
                        countTwitterShares: increment(
                            sum.countTwitterShares,
                            twitter,
                        ),
                        countTelegramShares: increment(
                            sum.countTelegramShares,
                            telegram,
                        ),
                        countWhatsappShares: increment(
                            sum.countWhatsappShares,
                            whatsapp,
                        ),
                        uids: sum.uids.concat(uids) // allow for duplicates
                    };
                    return sum;
                },
                initialShares,
            );
        };

        const countShared = await countShares(data.uid);
        const countInvitesUsed = await countUserInvites(data.uid);
        const countBillsVotedOn = await countUserVotesByLocale(data.uid);

        const totalCountShared = await countShares("total");
        const totalCountInvitesUsed = await countUserInvites("total");
        const totalCountBillsVotedOn = await countUserVotesByLocale("total");

        return {
            locale,
            userSway: {
                countInvitesUsed,
                countBillsVotedOn,
                ...countShared,
            },
            localeSway: {
                countInvitesUsed: totalCountInvitesUsed,
                countBillsVotedOn: totalCountBillsVotedOn,
                ...totalCountShared,
            },
        };
    },
);
