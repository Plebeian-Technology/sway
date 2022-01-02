import { LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { findLocale } from "@sway/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db } from "../firebase";
import { response } from "../httpTools";
// const { logger } = functions;
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

const handleError = (error: Error, message?: string) => {
    message && functions.logger.error(message);
    throw error;
};

// onRequest for external connections like Express (req/res)
export const createBillOfTheWeek = functions.https.onCall(
    async (data: IData, context: CallableContext) => {
        functions.logger.info(
            `create bill user email ${context?.auth?.token?.email}`,
        );
        functions.logger.info("data for creating new bill of the week");
        functions.logger.info({ data });
        if (!context?.auth) {
            functions.logger.error("unauthorized");
            return response(false, "error");
        }
        if (!context?.auth?.token?.email || !context?.auth?.uid) {
            functions.logger.error("unauthorized");
            return response(false, "error");
        }
        if (!data.localeName) {
            return response(false, "localeName must be included in payload");
        }

        const { localeName, positions, legislators, ...bill } = data;
        const locale = findLocale(localeName);
        if (!locale) {
            functions.logger.error(
                `Locale with name - ${localeName} - not in LOCALES. Skipping create bill of the week.`,
            );
            return;
        }

        const fireClient = new SwayFireClient(db, locale, functions.firestore);
        if (!fireClient) {
            functions.logger.error(
                "Failed to create fireClient with locale - ",
                locale,
            );
            return;
        }

        const userPlusAdmin: sway.IUserWithSettingsAdmin | null | void =
            await fireClient.users(context.auth.uid).get();
        if (!userPlusAdmin || !userPlusAdmin.isAdmin) {
            if (userPlusAdmin) {
                functions.logger.error(
                    "User is NOT an admin - UID - ",
                    userPlusAdmin.user.uid,
                );
            }
            return response(false, "error");
        }

        functions.logger.info("get firestore id from data");
        const id = data.firestoreId;
        if (!id) {
            return response(false, "firestoreId must be included in payload");
        }

        functions.logger.info("create insert bill object");

        const scoreErrorResponse = await createBillScore(
            fireClient,
            localeName,
            id,
        );
        if (scoreErrorResponse) return scoreErrorResponse;

        await updateOrganizations(fireClient, id, positions);

        await createLegislatorVotes(fireClient, id, legislators);

        functions.logger.info("creating bill of the week");
        try {
            await fireClient
                .bills()
                .create(id, { ...bill, active: true } as sway.IBill);
        } catch (error) {
            functions.logger.error(error);
            return response(false, "failed to insert bill of the week");
        }
        return;
    },
);

const createBillScore = async (
    legis: SwayFireClient,
    localeName: string,
    billFirestoreId: string,
): Promise<sway.IPlainObject | undefined> => {
    functions.logger.info(
        "creating bill scores for new bill of the week: ",
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
        functions.logger.error("failed to create bill score");
        functions.logger.error(error);
        return response(false, "failed to create bill score");
    }
    functions.logger.info("bill score created");
    return;
};

const initialDistrictBillScores = (localeName: string) => {
    const locale = LOCALES.find((l) => l.name === localeName);
    if (!locale)
        throw new Error(
            `Locale was not found when initiating scores. Passed in locale name - ${localeName}`,
        );

    return locale.districts.map((district: number) => ({
        for: 0,
        against: 0,
    }));
};

const updateOrganizations = async (
    legis: SwayFireClient,
    billFirestoreId: string,
    organizations: IDataOrganizationPositions,
): Promise<void> => {
    functions.logger.info(
        "updating organizations for new bill of the week: ",
        billFirestoreId,
    );
    for (const name in organizations) {
        const info = organizations[name];
        const org = await legis.organizations().get(name);
        if (!org) {
            functions.logger.warn(
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
    functions.logger.info(
        "creating legislator votes for new bill of the week: ",
        billFirestoreId,
        legislatorVotes,
    );
    for (const externalLegislatorId in legislatorVotes) {
        const vote = await legis
            .legislatorVotes()
            .get(externalLegislatorId, billFirestoreId)
            .catch(functions.logger.info);
        if (vote) {
            functions.logger.warn(
                `legislator - ${externalLegislatorId} - already has a vote cast on ${billFirestoreId}. skipping update`,
            );
            continue;
        }

        functions.logger.info(
            `creating vote on bill - ${billFirestoreId} - for legislator - ${externalLegislatorId}`,
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
