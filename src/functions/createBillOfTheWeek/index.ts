import { LOCALES } from "src/constants";
import SwayFireClient from "src/fire";
import { findLocale, isEmptyObject } from "src/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db } from "src/functions/firebase";
import { ISwayResponse, response } from "../httpTools";

interface IDataOrganizationPositions {
    [organizationName: string]: {
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

const { logger } = functions;
const handleError = (error: Error, message?: string) => {
    message && logger.error(message);
    throw error;
};

// onRequest for external connections like Express (req/res)
export const createBillOfTheWeek = functions.https.onCall(
    async (data: IData, context: CallableContext) => {
        logger.info(
            `createBillOfTheWeek - create bill user email ${context?.auth?.token?.email}`,
        );
        if (!context?.auth) {
            logger.error("unauthorized");
            return response(false, "error");
        }
        if (!context?.auth?.token?.email || !context?.auth?.uid) {
            logger.error("unauthorized");
            return response(false, "error");
        }

        logger.info(
            "createBillOfTheWeek - data for creating new bill of the week",
        );
        logger.info({ data });
        if (!data.localeName) {
            return response(false, "localeName must be included in payload");
        }

        const { localeName, positions, legislators, ...bill } = data;
        const locale = findLocale(localeName);
        if (!locale) {
            logger.error(
                `Locale with name - ${localeName} - not in LOCALES. Skipping create bill of the week.`,
            );
            return;
        }

        const fireClient = new SwayFireClient(db, locale, functions.firestore);
        if (!fireClient) {
            logger.error(
                "createBillOfTheWeek - Failed to create fireClient with locale - ",
                locale,
            );
            return;
        }

        const userPlusAdmin: sway.IUserWithSettingsAdmin | null | void =
            await fireClient.users(context.auth.uid).getWithSettings();

        if (!userPlusAdmin || !userPlusAdmin.isAdmin) {
            if (userPlusAdmin) {
                logger.error(
                    "createBillOfTheWeek - user is NOT an admin - UID - ",
                    userPlusAdmin.user.uid,
                );
            }
            return response(false, "error");
        }

        logger.info("createBillOfTheWeek - get firestore id from data");
        const id = data.firestoreId;
        if (!id) {
            return response(false, "firestoreId must be included in payload");
        }

        logger.info(
            "createBillOfTheWeek - creating bill object with scores, organizations and legislator votes",
        );
        const scoreErrorResponse = await createBillScore(
            fireClient,
            localeName,
            id,
        );
        if (scoreErrorResponse) return scoreErrorResponse;

        await updateOrganizations(fireClient, id, positions);

        await createLegislatorVotes(fireClient, id, legislators);

        logger.info(
            "createBillOfTheWeek - creating bill of the week from bill object",
        );
        try {
            await fireClient
                .bills()
                .create(id, { ...bill, active: true } as sway.IBill);
        } catch (error) {
            logger.error(error);
            return response(false, "failed to insert bill of the week");
        }
        return;
    },
);

const createBillScore = async (
    legis: SwayFireClient,
    localeName: string,
    billFirestoreId: string,
): Promise<ISwayResponse | undefined> => {
    logger.info(
        "createBillOfTheWeek.createBillScore - creating bill scores for new bill of the week: ",
        billFirestoreId,
    );
    try {
        await legis
            .billScores()
            .create(billFirestoreId, {
                districts: initialDistrictBillScores(localeName),
            })
            .catch((error: Error) =>
                handleError(error, "failed to create bill score"),
            );
    } catch (error) {
        logger.error("failed to create bill score");
        logger.error(error);
        return response(false, "failed to create bill score");
    }
    logger.info("bill score created");
    return;
};

const initialDistrictBillScores = (
    localeName: string,
): sway.IBillScoreDistrct => {
    const locale = LOCALES.find((l) => l.name === localeName);
    if (!locale) {
        throw new Error(
            `Locale was not found when initiating scores. Passed in locale name - ${localeName}`,
        );
    }
    if (isEmptyObject(locale.districts)) {
        throw new Error(
            `Locale has no districts when initiating scores. Passed in locale name - ${localeName}`,
        );
    }

    return (locale.districts as string[]).reduce(
        (sum: sway.IBillScoreDistrct, district: string) => ({
            ...sum,
            [district]: {
                for: 0,
                against: 0,
            },
        }),
        {},
    );
};

const updateOrganizations = async (
    legis: SwayFireClient,
    billFirestoreId: string,
    organizations: IDataOrganizationPositions,
): Promise<void> => {
    logger.info(
        "createBillOfTheWeek.updateOrganizations - updating organizations for new bill of the week: ",
        billFirestoreId,
    );
    for (const name in organizations) {
        const info = organizations[name];
        const org = await legis.organizations().get(name);
        if (!org) {
            logger.warn(
                `createBillOfTheWeek.updateOrganizations - could not find organization - ${name} - to update position on bill - ${billFirestoreId}. Organizations must be manually created.`,
            );
            continue;
        }
        await legis
            .organizations()
            .addPosition(name, billFirestoreId, {
                billFirestoreId,
                support: !!info.support,
                summary: info.position,
            })
            .catch(handleError);
    }
};

const createLegislatorVotes = async (
    legis: SwayFireClient,
    billFirestoreId: string,
    legislatorVotes: IDataLegislatorVotes,
): Promise<undefined> => {
    logger.info(
        "createBillOfTheWeek.createLegislatorVotes - creating legislator votes for new bill of the week: ",
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
                `legislator - ${externalLegislatorId} - already has a vote cast on billFirestoreId - ${billFirestoreId}. skipping update`,
            );
            continue;
        }

        logger.info(
            `createBillOfTheWeek.createLegislatorVotes - creating vote on bill.billFirestoreId - ${billFirestoreId} - for legislator - ${externalLegislatorId}`,
        );
        legis
            .legislatorVotes()
            .create(
                externalLegislatorId,
                billFirestoreId,
                legislatorVotes[externalLegislatorId],
            )
            .catch(handleError);
    }
    return;
};