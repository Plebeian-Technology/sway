import { WEB_PUSH_NOTIFICATION_TOPICS } from "src/constants";
import * as functions from "firebase-functions";
import { sway } from "sway";
import { messaging } from "../firebase";

const { logger } = functions;

export const sendWebPushNotification = (bill: sway.IBill) => {
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
