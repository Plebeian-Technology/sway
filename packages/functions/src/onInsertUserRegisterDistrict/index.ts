/** @format */

import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { sendSendgridEmail } from "../utils/email";
import { processUserLocation } from "../utils/geocode";

const { logger } = functions;

export const onInsertUserRegisterDistrict = functions.firestore
    .document("users/{uid}")
    .onCreate(async (snap: QueryDocumentSnapshot, context: EventContext) => {
        const doc: sway.IUser = snap.data() as sway.IUser;

        const sendWelcomeEmail = (success: boolean) => {
            if (!success) return;

            return sendSendgridEmail(
                doc.email,
                functions.config().sendgrid.welcometemplateid,
            ).then(() => true);
        };

        logger.info("Running geocode with OSM");
        return processUserLocation(snap, doc).then(sendWelcomeEmail);
    });
