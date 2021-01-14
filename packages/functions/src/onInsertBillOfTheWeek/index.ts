/** @format */

import {
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
    Support,
    WEB_PUSH_NOTIFICATION_TOPICS,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as sendgrid from "@sendgrid/mail";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
import { db, firestore, messaging } from "../firebase";
import { isEmptyObject } from "../utils";

// https://github.com/draftbit/twitter-lite/issues/111
// import Twitter from "twitter-lite";
const Twitter = require("twitter-lite");

const { logger } = functions;

export const onInsertBillOfTheWeek = functions.firestore
    .document("bills/{locale}/bills/{billFirestoreId}")
    .onCreate(async (snap: QueryDocumentSnapshot, context: EventContext) => {
        const config = functions.config();
        const bill = snap.data();
        if (!bill.active) {
            logger.error(
                "skipping onInsertBillOfTheWeek notifications. bill is not active.",
            );
            return;
        }

        const localeName = snap.ref?.parent?.parent?.id;
        logger.info("notifying new bill of the week for locale -", localeName);

        const getUsers = async (
            legis: SwayFireClient,
            uids: string[],
        ): Promise<sway.IUser[]> => {
            const snaps = uids.map((uid: string) =>
                legis.users(uid).getWithoutAdminSettings(),
            );
            const users = await Promise.all(snaps);
            return users.filter((u: sway.IUser | void) => !!u) as sway.IUser[];
        };

        const usersToNotify = async (
            legis: SwayFireClient,
            notificationTypes: number[],
        ): Promise<sway.IUser[] | void> => {
            const settingsSnap: fire.TypedQuerySnapshot<sway.IUserSettings> = await legis
                .userSettings("taco")
                .where(
                    "notificationFrequency",
                    "!=",
                    NOTIFICATION_FREQUENCY.Off,
                )
                .where("notificationType", "in", notificationTypes)
                .get();
            if (!settingsSnap) {
                logger.error("no user settings found to send notification to");
                return;
            }

            const settingsUids = settingsSnap.docs.map(
                (
                    setting: fire.TypedQueryDocumentSnapshot<sway.IUserSettings>,
                ) => setting.data().uid,
            );

            const users = await getUsers(legis, settingsUids);
            if (!users) return;

            return users;
        };

        const sendEmailNotification = async (legis: SwayFireClient) => {
            logger.info("preparing email notification");
            const users = await usersToNotify(legis, [
                NOTIFICATION_TYPE.Email,
                NOTIFICATION_TYPE.EmailSms,
            ]);

            logger.info("collecting user emails");
            const emails =
                users && !isEmptyObject(users)
                    ? users.map((user: sway.IUser) => user.email)
                    : [config.sendgrid.fromaddress];
            logger.info({ emails });
            logger.info("count of emails to send -", emails.length);

            sendgrid.setApiKey(config.sendgrid.apikey);

            const msg = {
                to: emails,
                from: config.sendgrid.fromaddress,
                templateId: config.sendgrid.templateid,
            };
            sendgrid.send(msg).then(logger.info).catch(logger.error);
        };

        const sendTweet = async (legis: SwayFireClient) => {
            logger.info("preparing tweet");
            const subdomain = "api";
            const version = "1.1";

            logger.info("create twitter client");
            const client = new Twitter({
                subdomain,
                version,
                consumer_key: config.twitter.consumer_key,
                consumer_secret: config.twitter.consumer_secret,
                access_token_key: config.twitter.access_token_key,
                access_token_secret: config.twitter.access_token_secret,
            });

            const tweetThread = async (thread: string[]) => {
                logger.info(`send tweet thread of length - ${thread.length}`);
                logger.info(thread);
                let lastTweetID = "";
                for (const status of thread) {
                    try {
                        const tweet = await client.post("statuses/update", {
                            status: status,
                            in_reply_to_status_id: lastTweetID,
                            auto_populate_reply_metadata: true,
                        });
                        lastTweetID = tweet.id_str;
                    } catch (error) {
                        logger.error("error posting thread in tweet. Error:");
                        logger.error(error);
                    }
                }
            };

            const thread = [
                `New Sway Bill of the Week - ${bill.externalId}\n\n${bill.title}\n\nhttps://app.sway.vote/bill-of-the-week`,
            ];

            const [supports, opposes, abstains]: [
                string,
                string,
                string,
            ] = await withLegislatorVotes(legis, bill as sway.IBill);
            logger.info("tweet: collected votes, tweeting tweet");
            tweetThread(
                thread
                    .concat(supports)
                    .concat(opposes)
                    .concat(abstains)
                    .filter(Boolean),
            );
        };

        const sendWebPushNotification = () => {
            logger.info("preparing web push notification message");
            const message = {
                data: {
                    title: "New Bill of the Week!",
                    body: `Bill ${bill.firestoreId}`,
                },
                topic: WEB_PUSH_NOTIFICATION_TOPICS.billOfTheWeekWeb,
            };
            logger.info(
                "sending web push notification message to topic - ",
                WEB_PUSH_NOTIFICATION_TOPICS.billOfTheWeekWeb,
            );
            messaging.send(message);
        };

        const legis = new SwayFireClient(
            db,
            { name: localeName } as sway.ILocale,
            firestore,
        );

        try {
            sendEmailNotification(legis).then(logger.info).catch(logger.error);
        } catch (error) {}
        try {
            sendWebPushNotification();
        } catch (error) {}
        sendTweet(legis)
            .then(() =>
                logger.info("tweet posted for bill - ", bill.firestoreId),
            )
            .catch((error) => {
                logger.error(error);
            });
    });

interface ILegislatorNameVote {
    twitter: string;
    support: string; // for | against | abstain
}

const withLegislatorVotes = async (
    legis: SwayFireClient,
    bill: sway.IBill,
): Promise<[string, string, string]> => {
    const defaultReturn: ["", "", ""] = ["", "", ""];
    logger.info("tweet: collecting legislator votes");
    try {
        const legislators = await legis.legislators().list();
        if (!legislators || legislators.length === 0) {
            logger.error(
                "legislators not collected, received empty list, to tweet legislator votes, skip adding legislator votes",
            );
            return defaultReturn;
        }
        const _legislatorVotes: (
            | ILegislatorNameVote
            | undefined
        )[] = await Promise.all(
            legislators.map(
                async (legislator: sway.ILegislator | undefined) => {
                    if (!legislator) return;

                    const vote: sway.ILegislatorVote | void = await legis
                        .legislatorVotes()
                        .get(legislator.externalId, bill.firestoreId);
                    if (!vote) return;
                    if (!legislator.twitter) return;

                    return {
                        twitter: legislator.twitter,
                        support: vote.support, // for | against | abstain,
                    };
                },
            ),
        );
        const legislatorVotes = _legislatorVotes.filter(Boolean);
        logger.info("collected legislator votes", legislatorVotes);
        if (isEmptyObject(legislatorVotes)) {
            logger.error(
                "no legislator votes. returning empty data to skip tweet",
            );
            return defaultReturn;
        }

        const supports: ILegislatorNameVote[] = legislatorVotes.filter(
            (lv) => lv?.support === Support.For,
        ) as ILegislatorNameVote[];
        const opposes: ILegislatorNameVote[] = legislatorVotes.filter(
            (lv) => lv?.support === Support.Against,
        ) as ILegislatorNameVote[];
        const abstains: ILegislatorNameVote[] = legislatorVotes.filter(
            (lv) => lv?.support === Support.Abstain,
        ) as ILegislatorNameVote[];

        const addTwitterHandle = (legislator: ILegislatorNameVote) => {
            const _twitter = legislator.twitter;
            if (!_twitter) return "";

            if (_twitter.startsWith("@")) {
                return _twitter;
            }
            return `@${_twitter}`;
        };

        const supportsString = supports.map(addTwitterHandle).join("\n");
        const opposesString = opposes.map(addTwitterHandle).join("\n");
        const abstainsString = abstains.map(addTwitterHandle).join("\n");

        return [
            supportsString
                ? `${bill.firestoreId} - For\n${supportsString}`
                : "",
            opposesString
                ? `${bill.firestoreId} - Against\n${opposesString}`
                : "",
            abstainsString
                ? `${bill.firestoreId} - Abstain\n${abstainsString}`
                : "",
        ];
    } catch (error) {
        logger.error("error collecting legislator votes. Error:");
        logger.error(error);
    }
    return defaultReturn;
};
