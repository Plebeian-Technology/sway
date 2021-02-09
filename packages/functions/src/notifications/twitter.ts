import SwayFireClient from "@sway/fire";
import { titleize } from "@sway/utils";
import * as functions from "firebase-functions";
import { sway } from "sway";
import Twitter from "twitter-lite";

const { logger } = functions;

export const sendTweet = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
) => {
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
        consumer_key: config.twitter.consumer_key,
        consumer_secret: config.twitter.consumer_secret,
        access_token_key: config.twitter.access_token_key,
        access_token_secret: config.twitter.access_token_secret,
    });

    const tweet = await client.post("statuses/update", {
        status: `#Sway #${titleize(
            locale.city,
        )} with a new Bill of the Week - ${bill.externalId}\n\n${
            bill.title
        }\n\nhttps://app.sway.vote/bill-of-the-week`,
    });

    logger.info("Tweet sent to twitter, received response:", tweet);
};
