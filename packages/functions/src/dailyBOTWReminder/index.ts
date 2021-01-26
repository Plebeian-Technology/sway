/** @format */

import {
    LOCALES
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { sendBotwEmailNotification } from "../notifications/email";
const { logger } = functions;

// every day at 15:00 EST
export const dailyBOTWReminder = functions.pubsub
    .schedule("0 15 * * *")
    .timeZone("America/New_York") // Users can choose timezone - default is America/Los_Angeles
    .onRun(async (context) => {
        logger.info(
            "running daily BOTW notification function for locales -",
            LOCALES.map((l: sway.ILocale) => l.name).join(", "),
        );
        const config = functions.config();

        LOCALES.forEach(async (locale: sway.ILocale) => {
            const fireClient = new SwayFireClient(db, locale, firestore);
            const bill = await fireClient.bills().latestCreatedAt();
            if (!bill) {
                logger.error(
                    `no latest bill of the week for locale - ${locale.name}. Skipping daily notification.`,
                );
                return;
            }
            if (!bill.active) {
                logger.warn(
                    "latest botw bill is not active. skipping daily notification for locale -",
                    locale.name,
                );
                return;
            }

            sendBotwEmailNotification(fireClient, config, bill, false)
        });
    });
