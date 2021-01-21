/** @format */

import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { response } from "../httpTools";
import {
    sendEmailNotification,
    sendTweet,
    sendWebPushNotification,
} from "../notifications";

const { logger } = functions;

interface IDataOrganizationPositions {
    [key: string]: {
        support?: boolean;
        oppose?: boolean;
        position: string;
    };
}

interface IDataLegislatorVotes {
    [key: string]: "for" | "against" | "abstain";
}
interface IData extends Partial<sway.IBill> {
    localeName: string;
    positions: IDataOrganizationPositions;
    legislators: IDataLegislatorVotes;
}

// onRequest for external connections like Express (req/res)
export const createBillOfTheWeek = functions.https.onCall(
    async (data: IData, context: CallableContext) => {
        logger.info(`create bill user email ${context?.auth?.token?.email}`);
        logger.info("data for creating new bill of the week");
        logger.info({ data });
        if (!context?.auth) {
            logger.error("unauthorized");
            return response(false, "error");
        }

        if (context?.auth?.token?.email !== "legis@sway.vote") {
            logger.error("unauthorized");
            return response(false, "error");
        }
        if (!data.localeName) {
            return response(false, "localeName must be included in payload");
        }

        const locale: sway.ILocale = {
            name: data.localeName,
        } as sway.ILocale;
        const legis = new SwayFireClient(db, locale, firestore);

        const userPlusAdmin: sway.IUserWithSettingsAdmin | null | void = await legis
            .users(context.auth.uid)
            .get();
        if (!userPlusAdmin || !userPlusAdmin.isAdmin) {
            return response(false, "error");
        }

        logger.info("get firestore id from data");
        const id = data.firestoreId;
        if (!id) {
            return response(false, "firestoreId must be included in payload");
        }

        logger.info("create insert bill object");
        const { localeName, positions, legislators, ...bill } = data;

        const scoreErrorResponse = await createBillScore(legis, id);
        if (scoreErrorResponse) return scoreErrorResponse;

        await updateOrganizations(legis, id, positions);

        await createLegislatorVotes(legis, id, legislators);

        logger.info("creating bill of the week");
        try {
            await legis
                .bills()
                .create(id, { ...bill, active: true } as sway.IBill);
        } catch (error) {
            logger.error(error);
            return response(false, "failed to insert bill of the week");
        }

        logger.info("successfully created bill of the week");
        return sendNotifications(bill as sway.IBill, localeName)
            .then(() => {
                return response(true, "bill created", bill as sway.IBill);
            })
            .catch(logger.error);
    },
);

const createBillScore = async (
    legis: SwayFireClient,
    billFirestoreId: string,
): Promise<sway.IPlainObject | undefined> => {
    logger.info(
        "creating bill scores for new bill of the week: ",
        billFirestoreId,
    );
    const users = await legis.users("").list();
    logger.info("building bill scores for each district");
    const usersEachDistrict =
        users &&
        users.reduce((sum: sway.IPlainObject, user: sway.IUser) => {
            const district = user.locale?.district;
            if (!district || sum[district]) return sum;

            sum[district] = {
                for: 0,
                against: 0,
            };
            return sum;
        }, {});

    logger.info("count of users in each district");
    logger.info(usersEachDistrict);
    try {
        await legis
            .billScores()
            .create(billFirestoreId, {
                districts: usersEachDistrict || {},
            })
            .catch((error: Error) => {
                logger.error("promise catch failed to create bill score");
                logger.error(error);
                return response(false, "failed to create bill score");
            });
    } catch (error) {
        logger.error("failed to create bill score");
        logger.error(error);
        return response(false, "failed to create bill score");
    }
    logger.info("bill score created");
    return;
};

const updateOrganizations = async (
    legis: SwayFireClient,
    billFirestoreId: string,
    organizations: IDataOrganizationPositions,
): Promise<void> => {
    logger.info(
        "updating organizations for new bill of the week: ",
        billFirestoreId,
    );
    for (const name in organizations) {
        const info = organizations[name];
        const org = await legis.organizations().get(name);
        if (!org) {
            logger.warn(
                `could not find organization - ${name} - to update position on bill - ${billFirestoreId}. Organizations must be manually created.`,
            );
            continue;
        }
        legis.organizations().addPosition(name, billFirestoreId, {
            billFirestoreId,
            support: !!info.support,
            summary: info.position,
        });
    }
};

const createLegislatorVotes = async (
    legis: SwayFireClient,
    billFirestoreId: string,
    legislatorVotes: IDataLegislatorVotes,
): Promise<sway.IPlainObject | undefined> => {
    logger.info(
        "creating legislator votes for new bill of the week: ",
        billFirestoreId,
        legislatorVotes,
    );
    for (const externalLegislatorId in legislatorVotes) {
        const vote = await legis
            .legislatorVotes()
            .get(externalLegislatorId, billFirestoreId)
            .catch(logger.info);
        if (vote) {
            logger.warn(
                `legislator - ${externalLegislatorId} - already has a vote cast on ${billFirestoreId}. skipping update`,
            );
            continue;
        }

        logger.info(
            `creating vote on bill - ${billFirestoreId} - for legislator - ${externalLegislatorId}`,
        );
        legis
            .legislatorVotes()
            .create(
                externalLegislatorId,
                billFirestoreId,
                legislatorVotes[externalLegislatorId],
            )
            .catch(logger.error);
    }
    return;
};

const sendNotifications = (bill: sway.IBill, localeName: string) => {
    const fireClient = new SwayFireClient(
        db,
        { name: localeName } as sway.ILocale,
        firestore,
    );

    try {
        sendEmailNotification(fireClient).then(logger.info).catch(logger.error);
    } catch (error) {}
    try {
        sendWebPushNotification(bill);
    } catch (error) {}

    return sendTweet(fireClient, bill)
        .then(() => logger.info("tweet posted for bill - ", bill.firestoreId))
        .catch((error) => {
            logger.error(error);
        });
};
