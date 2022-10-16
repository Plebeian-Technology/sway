/** @format */

import * as functions from "firebase-functions";
import { Change, EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { messaging } from "../firebase";
import { WEB_PUSH_NOTIFICATION_TOPICS, NOTIFICATION_TYPE } from "@sway/constants";

const { logger } = functions;

export const onUpdateUserSettings = functions.firestore
    .document("/user_settings/{userId}")
    .onUpdate(async (change: Change<QueryDocumentSnapshot>, _context: EventContext) => {
        const before: sway.IUserSettings = change.before.data() as sway.IUserSettings;
        const after: sway.IUserSettings = change.after.data() as sway.IUserSettings;

        const subscribeEmail =
            before.notificationType === null && after.notificationType === NOTIFICATION_TYPE.Email;

        const unsubscribeEmail =
            before.notificationType === NOTIFICATION_TYPE.Email && after.notificationType === null;

        const subscribeWebPush =
            !before.messagingRegistrationToken && after.messagingRegistrationToken;

        const unsubscribeWebPush =
            before.messagingRegistrationToken && !after.messagingRegistrationToken;

        const subscribeToEmailNotifications = () => {
            if (subscribeEmail) {
                logger.info("subscribing user to email notifications");
            } else if (unsubscribeEmail) {
                logger.info("unsubscribing user to email notifications");
            }
        };

        const subscribeToWebPushNotifications = () => {
            if (subscribeWebPush && after.messagingRegistrationToken) {
                logger.info("subscribing user to bill of the week topic");
                messaging
                    .subscribeToTopic(
                        [after.messagingRegistrationToken],
                        WEB_PUSH_NOTIFICATION_TOPICS.billOfTheWeekWeb,
                    )
                    .catch(console.error);
            } else if (unsubscribeWebPush && before.messagingRegistrationToken) {
                logger.info("unsubscribing user to bill of the week topic");
                messaging
                    .unsubscribeFromTopic(
                        [before.messagingRegistrationToken],
                        WEB_PUSH_NOTIFICATION_TOPICS.billOfTheWeekWeb,
                    )
                    .catch(console.error);
            }
        };

        subscribeToWebPushNotifications();
        subscribeToEmailNotifications();
    });
