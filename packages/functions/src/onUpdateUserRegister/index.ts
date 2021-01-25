/** @format */

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

            logger.info("Running geocode with OSM");
            return processUserLocation(snap, doc).then((success) => sendWelcomeEmail(doc.email, success));
        },
    );
