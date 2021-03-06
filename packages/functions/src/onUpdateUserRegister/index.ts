/** @format */

import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { Change, EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { sendWelcomeEmail } from "../notifications/email";
import { IFunctionsConfig } from "../utils";
import { processUserLocation } from "../utils/geocode";

const { logger } = functions;

export const onUpdateUserRegister = functions.firestore
    .document("users/{uid}")
    .onUpdate(
        async (
            change: Change<QueryDocumentSnapshot>,
            context: EventContext,
        ) => {
            const snap: QueryDocumentSnapshot = change.after;
            const doc: sway.IUser = snap.data() as sway.IUser;
            if (!doc) {
                logger.warn("no user");
                return false;
            }
            if (doc.isRegistrationComplete) {
                logger.warn("user already registered");
                return true;
            }

            const updateLocale = async (
                user: sway.IUser,
                uLocale: sway.IUserLocale,
            ) => {
                logger.info("Updating locale with new user -", uLocale.name);
                const fireClient = new SwayFireClient(db, uLocale, firestore);
                const usersLocale = await fireClient.locales().get(uLocale);
                if (!usersLocale) {
                    functions.logger.error(
                        "Failed to find uLocale in order to update count of users in locale -",
                        uLocale.name,
                    );
                    return;
                }

                await fireClient
                    .locales()
                    .addUserToCount(usersLocale, uLocale.district, {
                        addToAll: true,
                    })
                    .then((newLocale) => {
                        logger.info("Updated locale user count -", newLocale);
                    })
                    .catch(logger.error);

                if (uLocale.name === CONGRESS_LOCALE_NAME) {
                    await fireClient
                        .locales()
                        .addUserToCount(
                            usersLocale,
                            user.regionCode.toUpperCase(),
                            {
                                addToAll: false,
                            },
                        )
                        .then((newLocale) => {
                            logger.info(
                                "Updated CONGRESS locale district/state user count -",
                                newLocale,
                            );
                        })
                        .catch(logger.error);
                }
            };

            const config = functions.config() as IFunctionsConfig;
            return processUserLocation(snap, doc, config).then(
                (user: sway.IUser | null) => {
                    if (!user) return;
                    logger.info(
                        "Registered user, updating locales count-",
                        user.locales.length,
                    );
                    user.locales.forEach(async (userLocale, index, array) => {
                        updateLocale(user, userLocale)
                            .then(() => {
                                if (
                                    array.length === 1 ||
                                    userLocale.name !== CONGRESS_LOCALE_NAME
                                ) {
                                    sendWelcomeEmail(
                                        userLocale,
                                        config,
                                        user.email,
                                    );
                                }
                            })
                            .catch(console.error);
                    });
                },
            );
        },
    );
