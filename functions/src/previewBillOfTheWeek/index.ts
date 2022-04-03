import SwayFireClient from "@sway/fire";
import { findLocale } from "@sway/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { response } from "../httpTools";
import { sendSendgridEmail } from "../notifications";
import { IFunctionsConfig } from "../utils";

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

// onRequest for external connections like Express (req/res)
export const previewBillOfTheWeek = functions.https.onCall(
    async (data: IData, context: CallableContext) => {
        const config = functions.config() as IFunctionsConfig;

        logger.info(
            `previewBillOfTheWeek - create bill user email ${context?.auth?.token?.email}`,
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
            "previewBillOfTheWeek - data for creating new bill of the week",
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

        const fireClient = new SwayFireClient(db, locale, firestore, logger);
        if (!fireClient) {
            logger.error(
                "previewBillOfTheWeek - Failed to create fireClient with locale - ",
                locale,
            );
            return;
        }

        const userPlusAdmin: sway.IUserWithSettingsAdmin | null | void =
            await fireClient.users(context.auth.uid).getWithSettings();

        if (!userPlusAdmin || !userPlusAdmin.isAdmin) {
            if (userPlusAdmin) {
                logger.error(
                    "previewBillOfTheWeek - user is NOT an admin - UID - ",
                    userPlusAdmin.user.uid,
                );
            }
            return response(false, "error");
        }

        logger.info("previewBillOfTheWeek - get firestore id from data");
        const id = bill.firestoreId;
        if (!id) {
            return response(false, "firestoreId must be included in payload");
        }

        try {
            const newBill = { ...bill, active: true } as sway.IBill;
            handleEmailAdminsOnBillCreate(
                locale,
                config,
                newBill,
                positions,
                legislators,
            );
            return response(true, "Bill of the week created");
        } catch (error) {
            logger.error(error);
            return response(false, "Failed to create bill of the week");
        }
        return;
    },
);

const handleEmailAdminsOnBillCreate = async (
    locale: sway.ILocale,
    config: IFunctionsConfig,
    bill: sway.IBill,
    positions: IDataOrganizationPositions,
    legislators: IDataLegislatorVotes,
) => {
    logger.info(
        "previewBillOfTheWeek.handleEmailAdminsOnBillCreate - sending emails notifying botw created",
    );
    const templateId = "d-571067aa6d2e41cfa29e17f0718b537d";
    sendSendgridEmail(
        locale,
        config,
        ["dave@sway.vote", "legis@sway.vote"],
        templateId,
        {
            data: {
                ...bill,
                organizations: Object.keys(positions).map((key) => ({
                    ...positions[key],
                    name: key,
                })),
                legislators: Object.keys(legislators).map((key) => ({
                    id: key,
                    position: legislators[key],
                })),
            },
            isdevelopment: false,
        },
    );
};
