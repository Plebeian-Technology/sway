/** @format */

import { LOCALES } from "src/constants";
import SwayFireClient from "src/fire";
import * as functions from "firebase-functions";
import { sway } from "sway";
import { db, firestore } from "src/functions/firebase";
import { sendTweet } from "../notifications";
import { sendBotwEmailNotification } from "../notifications/email";
import { sendSMSNotification } from "../notifications/sms";
import { IFunctionsConfig } from "../utils";
const { logger } = functions;

// every day at 15:00 EST
export const dailyBOTWReminder = functions.pubsub
    .schedule("0 15 * * *")
    .timeZone("America/New_York") // Users can choose timezone - default is America/Los_Angeles
    .onRun((context: functions.EventContext) => {
        logger.info(
            "running daily BOTW notification function for locales -",
            LOCALES.map((l: sway.ILocale) => l.name).join(", "),
        );

        const config = functions.config() as IFunctionsConfig;

        let sentEmails = [] as string[];
        let sentSMS = [] as string[];

        const sendNotifications = async (
            fireClient: SwayFireClient,
            locale: sway.ILocale,
            bill: sway.IBill,
        ) => {
            const emailed = await sendBotwEmailNotification(
                fireClient,
                locale,
                config,
                bill,
                sentEmails,
            )
                .then((emails: string[]) => {
                    sentEmails = sentEmails.concat(emails);
                    return true;
                })
                .catch(logger.error);

            // try {
            //     sendWebPushNotification(bill);
            // } catch (error) {
            //     logger.error("error sending web push notification");
            //     logger.error(error);
            // }

            const texted = await sendSMSNotification(
                fireClient,
                locale,
                bill,
                sentSMS,
                config,
            )
                .then((phones: string[]) => {
                    sentSMS = sentSMS.concat(phones);
                    return true;
                })
                .catch(logger.error);

            if (bill.isTweeted) {
                logger.info(
                    "Skipping twitter tweet since bill has isTweeted === true",
                    bill.firestoreId,
                );
                return emailed;
            }

            const tweeted = await sendTweet(fireClient, config, bill)
                .then((posted: boolean | undefined) => {
                    if (!posted) return false;

                    logger.info("tweet posted for bill - ", bill.firestoreId);
                    return true;
                })
                .catch(logger.error);

            return tweeted && emailed && texted;
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

            await sendNotifications(fireClient, locale, bill)
                .then(async (successfullyNotified) => {
                    if (!successfullyNotified) return;

                    await fireClient.bills().update(
                        {
                            billFirestoreId: bill.firestoreId,
                        } as sway.IUserVote,
                        { isInitialNotificationsSent: true },
                    );
                })
                .catch(logger.error);
        });
    });
