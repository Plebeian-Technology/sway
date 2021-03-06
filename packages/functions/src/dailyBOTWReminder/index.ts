/** @format */

import { LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { sendTweet, sendWebPushNotification } from "../notifications";
import { sendBotwEmailNotification } from "../notifications/email";
import { IFunctionsConfig } from "../utils";
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

        const config = functions.config() as IFunctionsConfig;
        let sentEmails: string[] = [];

        const sendNotifications = async (
            fireClient: SwayFireClient,
            bill: sway.IBill,
            sentEmails: string[],
        ) => {
            const emailed = sendBotwEmailNotification(
                fireClient,
                config,
                bill,
                sentEmails,
            )
                .then((emails: string[]) => {
                    sentEmails = sentEmails.concat(emails);
                    return true;
                })
                .catch(logger.error);

            try {
                sendWebPushNotification(bill);
            } catch (error) {
                logger.error("error sending web push notification");
                logger.error(error);
            }

            if (bill.isTweeted) {
                logger.info(
                    "Skipping twitter tweet since bill has isTweeted === true",
                    bill.firestoreId,
                );
                return emailed;
            }

            const tweeted = sendTweet(fireClient, config, bill)
                .then(() => {
                    logger.info("tweet posted for bill - ", bill.firestoreId);
                    return true;
                })
                .catch(logger.error);

            if (!tweeted) return;
            return tweeted && emailed;
        };

        LOCALES.forEach(async (locale: sway.ILocale) => {
            const fireClient = new SwayFireClient(db, locale, firestore);
            const bill = await fireClient.bills().ofTheWeek();
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

            sendNotifications(fireClient, bill, sentEmails)
                .then((sentTweet) => {
                    if (!sentTweet) return;

                    fireClient.bills().update(
                        {
                            billFirestoreId: bill.firestoreId,
                        } as sway.IUserVote,
                        { isInitialNotificationsSent: true },
                    );
                })
                .catch(logger.error);
        });
    });
