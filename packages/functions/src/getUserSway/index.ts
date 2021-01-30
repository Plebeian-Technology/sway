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
        const { uid, locale } = data;
        if (!uid) {
            logger.error(
                "did not receive a uid, skipping user sway aggregation",
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

        const countUserVotesByLocale = async () => {
            return (await fireClient.userVotes(uid).list()).length;
        };
        const countUserInvites = async () => {
            const invites = await fireClient.userInvites(uid).get();
            if (!invites) return 0;

            return invites.emails.length;
        };
        const countShares = async (): Promise<{
            countBillsShared: number;
            countAllBillShares: number;
        }> => {
            const shares = await fireClient.userBillShares(uid).list();
            return shares.reduce(
                (
                    sum: {
                        countBillsShared: number;
                        countAllBillShares: number;
                    },
                    share: sway.IUserBillShare,
                ) => {
                    const billShares = Object.values(share).filter(Boolean);
                    const isSharedBill = billShares.length > 0;
                    sum = {
                        countBillsShared: isSharedBill
                            ? sum.countBillsShared + 1
                            : sum.countBillsShared,
                        countAllBillShares:
                            sum.countBillsShared + billShares.length,
                    };
                    return sum;
                },
                {
                    countBillsShared: 0, // if a user has shared a bill in any way
                    countAllBillShares: 0, // total number of ways in which a user has shared a bill
                },
            );
        };

        const shared = await countShares();
        const countInvitesUsed = await countUserInvites();
        const countBillsVotedOn = await countUserVotesByLocale();
        const countBillsShared = shared.countBillsShared;
        const countAllBillShares = shared.countAllBillShares;

        return {
            locale,
            userSway: {
                countInvitesUsed,
                countBillsVotedOn,
                countBillsShared,
                countAllBillShares,
            }
        };
    },
);
