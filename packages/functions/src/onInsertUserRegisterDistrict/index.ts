/** @format */

import { findLocale, toLocaleName } from "@sway/utils";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { sendWelcomeEmail } from "../notifications";
import { processUserLocation } from "../utils/geocode";

export const onInsertUserRegisterDistrict = functions.firestore
    .document("users/{uid}")
    .onCreate(async (snap: QueryDocumentSnapshot, context: EventContext) => {
        const doc: sway.IUser = snap.data() as sway.IUser;
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
    });
