/** @format */

import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { sendWelcomeEmail } from "../notifications";
import { processUserLocation } from "../utils/geocode";

const { logger } = functions;

export const onInsertUserRegisterDistrict = functions.firestore
    .document("users/{uid}")
    .onCreate(async (snap: QueryDocumentSnapshot, context: EventContext) => {
        const doc: sway.IUser = snap.data() as sway.IUser;
        const config = functions.config();

        const locale = doc.locales.find((l) => l.name !== CONGRESS_LOCALE_NAME);

        logger.info("Geocoding user");
        return processUserLocation(snap, doc).then((success: boolean) =>
            sendWelcomeEmail(
                new SwayFireClient(db, locale, firestore),
                config,
                doc.email,
                success,
            ),
        );
    });
