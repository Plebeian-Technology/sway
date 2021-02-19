import { WASHINGTON_DC_LOCALE_NAME } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { titleize } from "@sway/utils";
import * as functions from "firebase-functions";
import { sway } from "sway";
import Twitter from "twitter-lite";

const { logger } = functions;

const getTweetCity = (locale: sway.ILocale) => {
    if (locale.name !== WASHINGTON_DC_LOCALE_NAME) {
        return titleize(locale.city);
    }
    return "DC";
};

export const sendTweet = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
) => {
    if (bill.isTweeted) return;

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
            status: `#Sway #${titleize(
                getTweetCity(locale),
            )} with a new Bill of the Week - ${bill.externalId}\n\n${
                bill.title
            }\n\nhttps://app.sway.vote/bill-of-the-week`,
        })
        .then((tweetResponse) => {
            fireClient
                .bills()
                .update(
                    { billFirestoreId: bill.firestoreId } as sway.IUserVote,
                    {
                        isTweeted: true,
                    },
                );
            logger.info(
                "Tweet sent to twitter, received response:",
                tweetResponse,
            );
            return true;
        })
        .catch(logger.error);

    return tweeted;
};
