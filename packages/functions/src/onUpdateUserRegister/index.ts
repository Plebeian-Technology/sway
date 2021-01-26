/** @format */

import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { firestore } from "firebase-admin";
import * as functions from "firebase-functions";
import { Change, EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db } from "../firebase";
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

            const locale = doc.locales.find(
                (l) => l.name !== CONGRESS_LOCALE_NAME,
            );
            const config = functions.config();
            logger.info("Running geocode with OSM");
            return processUserLocation(snap, doc).then((success) =>
                sendWelcomeEmail(
                    new SwayFireClient(db, locale, firestore),
                    config,
                    doc.email,
                    success,
                ),
            );
        },
    );
