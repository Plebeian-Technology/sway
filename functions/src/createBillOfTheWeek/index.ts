import SwayFireClient from "@sway/fire";
import { findLocale, isEmptyObject } from "@sway/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/v1/https";
import { sway } from "sway";
import { LOCALES } from "../../constants";
import { db, firestoreConstructor } from "../firebase";
import { ISwayResponse, response } from "../httpTools";
import { sendSendgridEmail } from "../notifications";
import { IFunctionsConfig } from "../utils";

interface IDataOrganizationPositions {
    [organizationName: string]: {
        support?: boolean;
        oppose?: boolean;
        position: string;
    };
}
interface IOrg {
    label: string; // org name
    value: string; // org name
    iconPath: string;
    support: boolean;
    position: string;
}
interface IDataLegislatorVotes {
    [key: string]: sway.TLegislatorSupport;
}
interface IData extends Partial<sway.IBill> {
    localeName: string;
    positions: IDataOrganizationPositions;
    legislators: IDataLegislatorVotes;
    organizations: IOrg[];
}

const { logger } = functions;
const handleError = (error: Error, message?: string) => {
    message && logger.error(message);
    throw error;
};

// onRequest for external connections like Express (req/res)
export const createBillOfTheWeek = functions.https.onCall(
    async (data: IData, context: CallableContext) => {
        const config = functions.config() as IFunctionsConfig;

        logger.info(`createBillOfTheWeek - create bill user email ${context?.auth?.token?.email}`);
        if (!context?.auth) {
            logger.error("unauthorized");
            return response(false, "error");
        }
        if (!context?.auth?.token?.email || !context?.auth?.uid) {
            logger.error("unauthorized");
            return response(false, "error");
        }

        logger.info("createBillOfTheWeek - data for creating new bill of the week");
        logger.info({ data });
        if (!data.localeName) {
            return response(false, "localeName must be included in payload");
        }

        // eslint-disable-next-line
        const { localeName, positions, legislators, organizations, ...bill } = data;
        const locale = findLocale(localeName);
        if (!locale) {
            logger.error(
                `Locale with name - ${localeName} - not in LOCALES. Skipping create bill of the week.`,
            );
            return;
        }

        const fireClient = new SwayFireClient(db, locale, firestoreConstructor, logger);
        if (!fireClient) {
            logger.error(
                "createBillOfTheWeek - Failed to create fireClient with locale - ",
                locale,
            );
            return;
        }

        const userPlusAdmin: sway.IUserWithSettingsAdmin | null | void = await fireClient
            .users(context.auth.uid)
            .getWithSettings();

        if (!userPlusAdmin || !userPlusAdmin.isAdmin) {
            if (userPlusAdmin) {
                logger.error(
                    "createBillOfTheWeek - user is NOT an admin - UID - ",
                    userPlusAdmin.user.uid,
                );
            }
            return response(false, "error");
        }

        const newBill = { ...bill, active: true } as sway.IBill;

        logger.info("createBillOfTheWeek - get firestore id from data");
        const id = bill.firestoreId;
        if (!id) {
            return response(false, "firestoreId must be included in payload");
        }

        logger.info("createBillOfTheWeek - CREATING SCORES for bill -", bill.firestoreId);
        const scoreErrorResponse = await createBillScore(fireClient, localeName, id);
        if (scoreErrorResponse) return scoreErrorResponse;

        logger.info("createBillOfTheWeek - CREATING LEGISLATOR VOTES for bill -", bill.firestoreId);
        await createLegislatorVotes(fireClient, id, legislators);

        try {
            logger.info("createBillOfTheWeek - CREATING NEW BILL OF THE WEEK -", bill.firestoreId);
            await createBillAndOrganizations(fireClient, id, newBill, organizations)
                .then((created) => {
                    if (created) {
                        handleEmailAdminsOnBillCreate(
                            locale,
                            config,
                            {
                                ...created,
                                ...newBill,
                            },
                            legislators,
                        ).catch(logger.error);
                    }
                })
                .catch((error) => {
                    handleError(error, "Failed to create bill of the week.");
                });
            return response(true, "Bill of the week created");
        } catch (error) {
            logger.error(error);
            return response(false, "Failed to create bill of the week");
        }
    },
);

const createBillAndOrganizations = async (
    fireClient: SwayFireClient,
    id: string,
    newBill: sway.IBill,
    organizations: IOrg[],
): Promise<sway.IBill | undefined> => {
    const created = await fireClient.bills().create(id, newBill);

    organizations.forEach(async (o) => {
        logger.info(
            `createBillOfTheWeek - CREATING/UPDATING ORGANIZATION for bill - ${newBill.firestoreId}`,
            o,
        );
        fireClient
            .organizations()
            .get(o.value)
            .then((organization) => {
                if (organization) {
                    fireClient
                        .organizations()
                        .addPosition(organization.name, newBill.firestoreId, {
                            billFirestoreId: newBill.firestoreId,
                            support: !!o.support,
                            summary: o.position,
                        } as sway.IOrganizationPosition)
                        .catch(logger.error);
                } else {
                    fireClient
                        .organizations()
                        .create({
                            name: o.value,
                            iconPath: o?.iconPath || "",
                            positions: {
                                [newBill.firestoreId]: {
                                    billFirestoreId: newBill.firestoreId,
                                    support: !!o.support,
                                    summary: o.position,
                                },
                            },
                        })
                        .catch(logger.error);
                }
            })
            .catch(logger.error);
    });

    return created;
};

const handleEmailAdminsOnBillCreate = async (
    locale: sway.ILocale,
    config: IFunctionsConfig,
    bill: sway.IBill,
    legislators: IDataLegislatorVotes,
) => {
    logger.info(
        "createBillOfTheWeek.handleEmailAdminsOnBillCreate - sending emails notifying botw created",
    );
    const templateId = "d-571067aa6d2e41cfa29e17f0718b537d";
    sendSendgridEmail(locale, config, ["dave@sway.vote", "legis@sway.vote"], templateId, {
        data: {
            ...bill,
            legislators: Object.keys(legislators).map((key) => ({
                id: key,
                position: legislators[key],
            })),
        },
        isdevelopment: false,
    }).catch(logger.error);
};

const createBillScore = async (
    fireClient: SwayFireClient,
    localeName: string,
    billFirestoreId: string,
): Promise<ISwayResponse | undefined> => {
    logger.info(
        "createBillOfTheWeek.createBillScore - creating bill scores for new bill of the week: ",
        billFirestoreId,
    );
    try {
        await fireClient
            .billScores()
            .create(billFirestoreId, {
                districts: initialDistrictBillScores(localeName),
            })
            .catch((error: Error) => handleError(error, "failed to create bill score"));
    } catch (error) {
        logger.error("createBillOfTheWeek.createBillScore - failed to create bill score");
        logger.error(error);
        return response(false, "failed to create bill score");
    }
    logger.info("createBillOfTheWeek.createBillScore - BILL SCORE CREATED -", billFirestoreId);
    return;
};

const initialDistrictBillScores = (localeName: string): sway.IBillScoreDistrct => {
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

const createLegislatorVotes = async (
    fireClient: SwayFireClient,
    billFirestoreId: string,
    legislatorVotes: IDataLegislatorVotes,
): Promise<undefined> => {
    logger.info(
        "createBillOfTheWeek.createLegislatorVotes - creating legislator votes for new bill of the week: ",
        billFirestoreId,
        JSON.stringify(legislatorVotes),
    );
    const ids = Object.keys(legislatorVotes);
    for (const externalLegislatorId of ids) {
        logger.info(
            `createLegislatorVotes - check for existing vote on bill.billFirestoreId - ${billFirestoreId} - for legislator - ${externalLegislatorId}`,
        );
        const isVoteExists = await fireClient
            .legislatorVotes()
            .exists(externalLegislatorId, billFirestoreId)
            .catch((e) => {
                logger.error(
                    `createLegislatorVotes - error checking if vote exists for legislator - ${externalLegislatorId} on bill - ${billFirestoreId}. ERROR -`,
                    e,
                );
            });

        if (isVoteExists) {
            logger.warn(
                `createLegislatorVotes - legislator - ${externalLegislatorId} - already has a vote cast on billFirestoreId - ${billFirestoreId}. skipping update`,
            );
        } else {
            logger.info(
                `createLegislatorVotes - creating vote on bill.billFirestoreId - ${billFirestoreId} - for legislator - ${externalLegislatorId}`,
            );
            fireClient
                .legislatorVotes()
                .create(
                    externalLegislatorId,
                    billFirestoreId,
                    legislatorVotes[externalLegislatorId],
                )
                .catch((e) => {
                    logger.error(
                        `createLegislatorVotes - error creating vote for legislator - ${externalLegislatorId} on bill - ${billFirestoreId}. ERROR -`,
                        e,
                    );
                });
        }
    }
    logger.info("createBillOfTheWeek.createLegislatorVotes - FINISHED");
    return;
};
