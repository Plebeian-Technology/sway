/** @format */

import { findLocale, toLocaleName } from "@sway/utils";
import * as functions from "firebase-functions";
import { Change, EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { sendWelcomeEmail } from "../notifications/email";
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

            const config = functions.config();
            return processUserLocation(snap, doc).then(
                (user: sway.IUser | null) => {
                    if (user) {
                        const localeName = toLocaleName(
                            doc.city,
                            doc.region,
                            doc.country,
                        );
                        const locale = findLocale(localeName);
                        sendWelcomeEmail(locale, config, user.email);
                    }
                },
            );
        },
    );
