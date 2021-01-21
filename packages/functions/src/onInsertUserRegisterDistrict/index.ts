/** @format */

import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { sendWelcomeEmail } from "../notifications";
import { processUserLocation } from "../utils/geocode";

const { logger } = functions;

export const onInsertUserRegisterDistrict = functions.firestore
    .document("users/{uid}")
    .onCreate(async (snap: QueryDocumentSnapshot, context: EventContext) => {
        const doc: sway.IUser = snap.data() as sway.IUser;

        logger.info("Running geocode with OSM");
        return processUserLocation(snap, doc).then((success: boolean) =>
            sendWelcomeEmail(doc.email, success),
        );
    });
