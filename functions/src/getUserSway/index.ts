/** @format */

import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import get from "lodash.get";
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
    async (data: IData, context: CallableContext): Promise<IResponseData | undefined> => {
        if (context?.auth?.uid !== data?.uid) {
            logger.error("auth uid does not match data uid, skipping user sway aggregation");
            return;
        }
        logger.info("getting user sway");
        const { locale } = data;
        if (!data.uid) {
            logger.error("did not receive a data.uid, skipping user sway aggregation");
            return;
        }
        if (!locale) {
            logger.error("did not receive a locale, skipping user sway aggregation");
            return;
        }

        const fireClient = new SwayFireClient(db, locale, firestore, logger);

        const countUserVotesByLocale = async (uid: string | "total") => {
            return (await fireClient.userVotes(uid).getAll()).length;
        };
        const countUserInvites = async (uid: string | "total"): Promise<[number, number]> => {
            const invites = await fireClient.userInvites(uid).get();
            if (!invites) {
                return [0, 0];
            }

            return [invites.sent.length, invites.redeemed.length];
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

        const countShares = async (uid: string | "total"): Promise<ICountShares> => {
            const shares = await fireClient.userBillShares(uid).list();
            return shares.reduce((sum: ICountShares, share: sway.IUserBillShare) => {
                const billShares = Object.values(share.platforms).filter(Boolean);
                const isSharedBill = billShares.length > 0;
                const {
                    uids,
                    platforms: { facebook, twitter, whatsapp, telegram },
                } = share;
                return {
                    countAllBillShares: sum.countBillsShared + billShares.length,
                    countBillsShared: sum.countBillsShared + Number(isSharedBill),
                    countFacebookShares: increment(sum.countFacebookShares, facebook),
                    countTwitterShares: increment(sum.countTwitterShares, twitter),
                    countTelegramShares: increment(sum.countTelegramShares, telegram),
                    countWhatsappShares: increment(sum.countWhatsappShares, whatsapp),
                    uids: sum.uids.concat(uids), // allow for duplicates
                };
            }, initialShares);
        };

        const calculateAggregateSway = (usersSway: sway.IUserSway) => {
            return Object.keys(usersSway).reduce((sum: number, key: string) => {
                if (key.includes("count")) {
                    if (key === "countBillsVotedOn") {
                        return sum + get(usersSway, key) * 10;
                    }
                    return sum + get(usersSway, key);
                }
                return sum;
            }, 0);
        };

        const countShared = await countShares(data.uid);
        const [countInvitesSent, countInvitesRedeemed] = await countUserInvites(data.uid);
        const countBillsVotedOn = await countUserVotesByLocale(data.uid);

        const totalCountShared = await countShares("total");
        const [totalCountInvitesSent, totalCountInvitesRedeemed] = await countUserInvites("total");
        const totalCountBillsVotedOn = await countUserVotesByLocale("total");

        const userSway = {
            countInvitesSent,
            countInvitesRedeemed,
            countBillsVotedOn,
            ...countShared,
        } as sway.IUserSway;

        const localeSway = {
            countInvitesSent: totalCountInvitesSent,
            countInvitesRedeemed: totalCountInvitesRedeemed,
            countBillsVotedOn: totalCountBillsVotedOn,
            ...totalCountShared,
        } as sway.IUserSway;

        const userSwayTotal = calculateAggregateSway(userSway);
        const localeSwayTotal = calculateAggregateSway(localeSway);

        return {
            locale,
            userSway: { ...userSway, totalSway: userSwayTotal },
            localeSway: { ...localeSway, totalSway: localeSwayTotal },
        };
    },
);
