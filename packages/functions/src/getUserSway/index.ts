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

        interface ICountShares {
            countBillsShared: number;
            countAllBillShares: number;
            countFacebookShares: number;
            countTwitterShares: number;
            countTelegramShares: number;
            countWhatsappShares: number;
        }

        const initialShares: ICountShares = {
            countBillsShared: 0, // if a user has shared a bill in any way
            countAllBillShares: 0, // total number of ways in which a user has shared a bill
            countFacebookShares: 0,
            countTwitterShares: 0,
            countTelegramShares: 0,
            countWhatsappShares: 0,
        };

        const updateCount = (sum: number, item: boolean | undefined) => {
            return item ? sum + 1 : sum
        }

        const countShares = async (): Promise<ICountShares> => {
            const shares = await fireClient.userBillShares(uid).list();
            return shares.reduce(
                (sum: ICountShares, share: sway.IUserBillShare) => {
                    const billShares = Object.values(share).filter(Boolean);
                    const isSharedBill = billShares.length > 0;
                    const {
                        platforms: { facebook, twitter, whatsapp, telegram },
                    } = share;
                    sum = {
                        countBillsShared: updateCount(sum.countBillsShared, isSharedBill),
                        countAllBillShares:
                            sum.countBillsShared + billShares.length,
                        countFacebookShares: updateCount(sum.countFacebookShares, facebook),
                        countTwitterShares: updateCount(sum.countTwitterShares, twitter),
                        countTelegramShares: updateCount(sum.countTelegramShares, telegram),
                        countWhatsappShares: updateCount(sum.countWhatsappShares, whatsapp),
                    };
                    return sum;
                },
                initialShares,
            );
        };

        const countShared = await countShares();
        const countInvitesUsed = await countUserInvites();
        const countBillsVotedOn = await countUserVotesByLocale();

        return {
            locale,
            userSway: {
                countInvitesUsed,
                countBillsVotedOn,
                ...countShared,
            },
        };
    },
);
