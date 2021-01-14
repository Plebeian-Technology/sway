/** @format */

import {
    Collections,
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { DocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
import { db, firestore } from "../firebase";
import { isEmptyObject } from "../utils";
import { sendSendgridEmail } from "../utils/email";
const { logger } = functions;

// every day at 15:00 EST
export const dailyBOTWReminder = functions.pubsub
    .schedule("0 15 * * *")
    .timeZone("America/New_York") // Users can choose timezone - default is America/Los_Angeles
    .onRun(async (context) => {
        const locales = await SwayFireClient.Locales(db);
        logger.info(
            "running daily BOTW notification function for locales -",
            locales.map((l) => l.name).join(", "),
        );

        locales.forEach(async (locale: sway.ILocale) => {
            const legis = new SwayFireClient(
                db,
                { name: locale.name } as sway.ILocale,
                firestore,
            );
            const bill = await legis.bills().latest();
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

            const isUserVoted = (snap: DocumentSnapshot) => {
                return snap && snap.exists;
            };

            const userVoteDocumentPath = (uid: string) => {
                return `${Collections.UserVotes}/${locale.name}/${uid}/${bill.firestoreId}`;
            };

            const getNotVotedUserEmails = async (
                uids: string[],
            ): Promise<string[]> => {
                const allUids: (string | null)[] = await Promise.all(
                    uids.map(
                        async (uid: string): Promise<string | null> => {
                            const doc = db.doc(userVoteDocumentPath(uid));
                            const snap = await doc.get();
                            return !isUserVoted(snap) ? uid : null;
                        },
                    ),
                );

                const hasNotVotedUids: string[] = allUids.filter(
                    Boolean,
                ) as string[];
                const emails: (string | null)[] = await Promise.all(
                    hasNotVotedUids.map(async (uid: string) => {
                        const user = await legis
                            .users(uid)
                            .getWithoutAdminSettings();
                        if (!user) return null;
                        return user.email;
                    }),
                );
                return emails.filter(Boolean) as string[];
            };

            const usersToNotify = async (): Promise<string[] | void> => {
                const settingsSnap: fire.TypedQuerySnapshot<sway.IUserSettings> = await legis
                    .userSettings("taco")
                    .where(
                        "notificationFrequency",
                        "==",
                        NOTIFICATION_FREQUENCY.Daily,
                    )
                    .where("notificationType", "in", [
                        NOTIFICATION_TYPE.Email,
                        NOTIFICATION_TYPE.EmailSms,
                    ])
                    .get();
                if (!settingsSnap) {
                    logger.error(
                        "no user settings found to send notification to",
                    );
                    return;
                }

                const settingsUids = settingsSnap.docs.map(
                    (
                        setting: fire.TypedQueryDocumentSnapshot<sway.IUserSettings>,
                    ) => setting.data().uid,
                );

                const users = await getNotVotedUserEmails(settingsUids);
                if (!users) return;

                return users;
            };

            logger.info("collecting user emails for daily email notification");
            const emails = await usersToNotify();
            if (!emails) {
                logger.warn("no emails found, skipping daily email send");
                return;
            }
            logger.info("count of emails to send -", emails.length);
            return sendSendgridEmail(
                !isEmptyObject(emails)
                    ? emails
                    : [functions.config().sendgrid.fromaddress],
                functions.config().sendgrid.templateid,
            ).then(() => true);
        });
    });
