/** @format */

import { CONGRESS_LOCALE, Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isAtLargeLocale, isCongressLocale, isEmptyObject } from "@sway/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import fetch from "node-fetch";
import { fire, sway } from "sway";
import { db, firestore } from "../firebase";
import get from "lodash.get";

const xml2js = require("xml2js");
const xmlParser = xml2js.Parser();

const { logger } = functions;

interface IData {
    uid: string;
    billFirestoreId: string;
    rollCall: number | string;
}

type TSwayVoteSupport = "for" | "against" | "abstain";

interface ISwayLegislatorVote {
    [billid: string]: {
        [legislatorid: string]: TSwayVoteSupport;
    };
}

interface ICongressDotGovVote {
    legislator: [
        {
            _: string;
            $: {
                "name-id": string;
                "sort-field": string;
                "unaccented-name": string;
                party: "R" | "D" | "I";
                state: string;
                role: "legislator";
            };
        },
    ];
    vote: [string];
}

const handleError = (error: Error, message?: string) => {
    message && logger.error(message);
    throw error;
};

// every day at 23:00 EST
export const updateLegislatorVotes = functions.https.onCall(
    async (data: IData, context: CallableContext) => {
        if (!context?.auth?.uid || context?.auth.uid !== data.uid) {
            logger.error("Unauthed request to updateLegislatorVotes");
            return "Invalid Credentials.";
        }

        logger.info("Running legislator vote update for Congress");
        const { uid, billFirestoreId, rollCall } = data;

        const legislatorVotesUrl = getVoteEndpoint(rollCall.toString());

        const swayFire = new SwayFireClient(db, CONGRESS_LOCALE, firestore);

        const legislators = await swayFire.legislators().list();
        if (!legislators) {
            logger.error("No congressionals legislators found.");
            return;
        }

        const isLegislatorVoteExists = async (
            legislatorId: string,
        ): Promise<boolean> => {
            return await swayFire
                .legislatorVotes()
                .exists(legislatorId, billFirestoreId);
        };

        const getLegislator = async (
            legislatorId: string,
        ): Promise<sway.ILegislator | undefined> => {
            return await swayFire.legislators().get(legislatorId);
        };

        const isUserLocaleDistrict = (
            locale: sway.IUserLocale,
            legislatorDistrict: string,
        ) => {
            return (
                isAtLargeLocale(locale) ||
                locale.district === legislatorDistrict
            );
        };

        const usersInMatchingDistrict = (
            users: fire.TypedQueryDocumentSnapshot<sway.IUser>[],
            legislatorDistrict: string,
        ): sway.IUser[] => {
            return users
                .map((doc: fire.TypedDocumentSnapshot<sway.IUser>) =>
                    doc?.data(),
                )
                .filter((user: sway.IUser | undefined) => {
                    if (!user) return false;
                    const locale = user.locales?.find(isCongressLocale);
                    if (!locale) return false;
                    return isUserLocaleDistrict(locale, legislatorDistrict);
                }) as sway.IUser[];
        };

        const getUsersInRegionDistrict = async (
            regionCode: string,
            legislatorDistrict: string,
        ) => {
            return swayFire
                .users(uid)
                .where("regionCode", "==", regionCode)
                .get()
                .then((snap) =>
                    usersInMatchingDistrict(snap.docs, legislatorDistrict),
                )
                .catch(handleError);
        };

        const getUserVote = async (
            _uid: string,
        ): Promise<sway.IUserVote | undefined> => {
            return await swayFire.userVotes(_uid).get(billFirestoreId);
        };

        const upsertUserLegislatorVote = async (
            _uid: string,
            userVote: sway.IUserVote,
            externalLegislatorId: string,
            legislatorSupport: TSwayVoteSupport,
        ): Promise<string | undefined> => {
            return swayFire
                .userLegislatorVotes(_uid)
                .create(
                    userVote.support as string,
                    legislatorSupport,
                    userVote.billFirestoreId,
                    externalLegislatorId,
                )
                .then((ref) => ref?.path)
                .catch(handleError);
        };

        const createLegislatorVote = async (
            legislatorId: string,
            legislatorSupport: TSwayVoteSupport,
        ): Promise<sway.ILegislatorVote | undefined> => {
            return await swayFire
                .legislatorVotes()
                .create(legislatorId, billFirestoreId, legislatorSupport);
        };

        return fetchLegislatorVotes(legislatorVotesUrl)
            .then((votes) => {
                return legislatorVotesOnBill(
                    billFirestoreId,
                    votes,
                    legislators.filter(Boolean) as sway.ILegislator[],
                );
            })
            .then((votes: ISwayLegislatorVote) => {
                const legislatorVotes = votes[billFirestoreId];
                const legislatorIds = Object.keys(legislatorVotes);

                legislatorIds.forEach(async (legislatorId: string) => {
                    const legislator = await getLegislator(legislatorId);
                    if (!legislator) {
                        throw new Error(
                            `No legislator asssociated with id - ${legislatorId}`,
                        );
                    }

                    const exists = await isLegislatorVoteExists(legislatorId);
                    if (exists) {
                        throw new Error(
                            `Legislator vote already exists for bill - ${billFirestoreId} and legislator - ${legislatorId}`,
                        );
                    }

                    const users: sway.IUser[] = await getUsersInRegionDistrict(
                        legislator.regionCode,
                        legislator.district,
                    );
                    if (!users || isEmptyObject(users)) {
                        logger.info(
                            `No users found in legislator regionCode - ${legislator.regionCode}`,
                        );
                        return;
                    }

                    const legislatorSupport = legislatorVotes[legislatorId];
                    const newVote = await createLegislatorVote(
                        legislatorId,
                        legislatorSupport,
                    );
                    if (!newVote) {
                        throw new Error(
                            `Failed to create legislator vote for legislator - ${legislatorId} - bill - ${billFirestoreId} - support - ${legislatorSupport}`,
                        );
                    }

                    users.forEach(async (user) => {
                        const userVote = await getUserVote(user.uid);
                        if (!userVote?.support) return;

                        const userLegislatorVoteRefPath = await upsertUserLegislatorVote(
                            user.uid,
                            userVote,
                            legislatorId,
                            legislatorSupport,
                        );
                        if (!userLegislatorVoteRefPath) {
                            throw new Error(
                                `Unable to get or create user legislator vote with - userVote: ${userVote} - legislatorId: ${legislatorId} - legislatorSupport: ${legislatorSupport}`,
                            );
                        }

                        await swayFire
                            .userLegislatorScores()
                            .update(
                                legislator,
                                newVote,
                                userVote,
                                userLegislatorVoteRefPath,
                                user.uid,
                            );
                    });
                });
            })
            .catch(handleError);
    },
);

const legislatorVotesOnBill = (
    billFirestoreId: string,
    votes: ICongressDotGovVote[],
    legislators: sway.ILegislator[],
): ISwayLegislatorVote => ({
    [billFirestoreId]: legislators.reduce(
        (
            sum: { [legislatorId: string]: TSwayVoteSupport },
            legislator: sway.ILegislator | undefined,
        ) => {
            if (!legislator) return sum;

            const obj = matchLegislatorToVote(legislator, votes);
            sum = {
                ...sum,
                ...obj,
            };
            return sum;
        },
        {},
    ),
});

const toSwaySupport = (position: string) => {
    if (position === "yea") return Support.For;
    if (position === "nay") return Support.Against;
    if (position === "not voting") return Support.Abstain;
    throw new Error(`POSITION WAS - ${position}`);
};

const matchLegislatorToVote = (
    legislator: sway.IBasicLegislator,
    votes: ICongressDotGovVote[],
): { [legislatorId: string]: TSwayVoteSupport } => {
    const position:
        | ICongressDotGovVote
        | undefined = votes.find((vote: ICongressDotGovVote) =>
        findLegislatorPosition(vote, legislator),
    );
    if (!position) {
        console.log("No vote for legislator -", legislator.bioguideId);
        return {};
    }
    console.log(
        "Adding legislator support -",
        legislator.externalId,
        toSwaySupport(position?.vote[0].toLowerCase()),
    );
    return {
        [legislator.externalId]: toSwaySupport(position?.vote[0].toLowerCase()),
    };
};

const getVoteEndpoint = (rollCall: string) => {
    // return `https://api.propublica.org/congress/v1/${congress}/${chamber}/sessions/${session}/votes/${rollCall}.json`;
    while (rollCall.length < 3) {
        rollCall = "0" + rollCall;
    }
    const year = new Date().getFullYear();
    return `https://clerk.house.gov/evs/${year}/roll${rollCall}.xml`;
};

const getXML = (url: string) => {
    console.log("FETCHING XML -", url);

    return fetch(url)
        .then((res) => res.text())
        .catch(console.error);
};

const fetchLegislatorVotes = (endpoint: string) => {
    return getXML(endpoint).then((result: any) => {
        return xmlParser.parseStringPromise(result).then((res: any) => {
            return get(res, "rollcall-vote.vote-data.0.recorded-vote");
        });
    });
};

const findLegislatorPosition = (
    vote: ICongressDotGovVote,
    legislator: sway.IBasicLegislator,
) => {
    return get(vote, "legislator.0.$.name-id") === legislator.bioguideId;
};
