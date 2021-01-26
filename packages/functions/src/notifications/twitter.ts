import { Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { sway } from "sway";
import { isEmptyObject } from "../utils";

const Twitter = require("twitter-lite");

const { logger } = functions;

interface ILegislatorNameVote {
    twitter: string;
    support: string; // for | against | abstain
}

export const sendTweet = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
) => {
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
    ] = await withLegislatorVotes(fireClient, bill as sway.IBill);
    logger.info("tweet: collected votes, tweeting tweet");
    tweetThread(
        thread
            .concat(supports)
            .concat(opposes)
            .concat(abstains)
            .filter(Boolean),
    );
};

const withLegislatorVotes = async (
    fireClient: SwayFireClient,
    bill: sway.IBill,
): Promise<[string, string, string]> => {
    const defaultReturn: ["", "", ""] = ["", "", ""];
    logger.info("tweet: collecting legislator votes");
    try {
        const legislators = await fireClient.legislators().list();
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

                    const vote: sway.ILegislatorVote | void = await fireClient
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
            `${bill.firestoreId} - For\n${
                supportsString ? supportsString : "None"
            }`,

            `${bill.firestoreId} - Against\n${
                opposesString ? opposesString : "None"
            }`,

            `${bill.firestoreId} - Abstain\n${
                abstainsString ? abstainsString : "None"
            }`,
        ];
    } catch (error) {
        logger.error("error collecting legislator votes. Error:");
        logger.error(error);
    }
    return defaultReturn;
};
