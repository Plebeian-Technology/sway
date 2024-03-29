import { WASHINGTON_DC_LOCALE_NAME } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { titleize } from "@sway/utils";
import * as functions from "firebase-functions";
import { sway } from "sway";

// eslint-disable-next-line
const Twitter = require("twitter-lite");

const { logger } = functions;

const getTweetCity = (locale: sway.ILocale) => {
    if (locale.name !== WASHINGTON_DC_LOCALE_NAME) {
        return locale.city
            .split("_")
            .map((s) => titleize(s))
            .join("");
    }
    return "DC";
};

export const sendTweet = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
) => {
    if (bill.isTweeted) return;
    if (config.sway.isdevelopment && config.sway.isdevelopment !== "false") {
        logger.info(
            "sendTweet - is dev, skip posting tweet for locale -",
            fireClient?.locale?.name,
        );
        return true;
    }

    const locale = fireClient.locale;
    if (!locale) {
        logger.error("Locale is undefined in sendTweet");
        return;
    }

    logger.info("preparing tweet");
    const subdomain = "api";
    const version = "1.1";

    logger.info("create twitter client");
    const client = new Twitter({
        subdomain,
        version,
        consumer_key: config.twitter2.consumer_key,
        consumer_secret: config.twitter2.consumer_secret,
        access_token_key: config.twitter2.access_token_key,
        access_token_secret: config.twitter2.access_token_secret,
    });

    const tweeted = await client
        .post("statuses/update", {
            status: `#Sway #${getTweetCity(locale)} with a new Bill of the Week - ${
                bill.externalId
            }\n\n${bill.title}\n\nhttps://app.sway.vote/bill-of-the-week?locale=${locale.name}`,
        })
        .then((tweetResponse: any) => {
            fireClient
                .bills()
                .update({ billFirestoreId: bill.firestoreId } as sway.IUserVote, {
                    isTweeted: true,
                })
                .catch(logger.error);
            logger.info("Tweet sent to twitter, received response:", tweetResponse);
            return true;
        })
        .catch(logger.error);

    return tweeted;
};
