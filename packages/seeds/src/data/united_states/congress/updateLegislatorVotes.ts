import * as fs from "fs";
import fetch, { Response } from "node-fetch";
import { Support } from "@sway/constants";
import { sway } from "sway";
import billsData from "./congress/bills";
import legislatorsData from "./congress/legislators";
import legislatorVotes from "./congress/legislator_votes";
import { get } from "lodash";

const xml2js = require("xml2js");
const xmlParser = xml2js.Parser();

const CONGRESS = 117;

const PROPUBLICA_HEADERS = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "X-API-Key": process.env.PROPUBLICA_API_KEY || "",
};

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

const bills = billsData.united_states.congress.congress as sway.IBill[];
const legislators = legislatorsData.united_states.congress
    .congress as sway.IBasicLegislator[];
const currentVotes = legislatorVotes.united_states.congress.congress as {
    [billid: string]: {
        [legislatorExternalId: string]: string;
    };
};

// 1 or 2, depending on year (1 is odd-numbered years, 2 is even-numbered years)
const congressionalSession = () => {
    const date = new Date();
    const year = date.getFullYear();
    return year % 2 === 0 ? 2 : 1;
};

const getVotesEndpoint = (chamber: string, year: string, month: string) => {
    return `https://api.propublica.org/congress/v1/${chamber}/votes/${year}/${month}.json`;
};

const getVoteEndpoint = (rollCall: string) => {
    // return `https://api.propublica.org/congress/v1/${congress}/${chamber}/sessions/${session}/votes/${rollCall}.json`;
    while (rollCall.length < 3) {
        rollCall = "0" + rollCall;
    }
    const year = new Date().getFullYear();
    return `https://clerk.house.gov/evs/${year}/roll${rollCall}.xml`;
};

const getJSON = (url: string) => {
    console.log("FETCHING -", url);

    return fetch(url, { headers: PROPUBLICA_HEADERS })
        .then((res) => res.json())
        .catch(console.error);
};

const getXML = (url: string) => {
    console.log("FETCHING XML -", url);

    return fetch(url)
        .then((res) => res.text())
        .catch(console.error);
};

const toSwaySupport = (position: string) => {
    if (position === "yea") return Support.For;
    if (position === "nay") return Support.Against;
    if (position === "not voting") return Support.Abstain;
    throw new Error(`POSITION WAS - ${position}`);
};

const fetchVoteDetails = (bill: sway.IBill, endpoint: string) => {
    return getJSON(endpoint).then((result: any) => {
        console.log("RESULT");
        const votes: any[] = result.results.votes;
        console.log("retrieved votes from propublica", votes.length);

        const vote = votes.find(
            (v: any) =>
                v.bill_id === bill.externalId ||
                v?.bill?.bill_id === bill.externalId,
        );
        console.log("VOTE");
        console.log(vote);
        if (!vote) {
            console.dir(votes, { depth: null });
            return null;
        }
        return vote;
    });
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

const matchLegislatorToVote = (
    sum: any,
    legislator: sway.IBasicLegislator,
    votes: ICongressDotGovVote[],
) => {
    const position:
        | ICongressDotGovVote
        | undefined = votes.find((vote: ICongressDotGovVote) =>
        findLegislatorPosition(vote, legislator),
    );
    if (!position) {
        console.log("NO VOTE FOR LEGISLATOR", legislator.bioguideId);
        return sum;
    }
    sum = {
        ...sum,
        [legislator.externalId]: toSwaySupport(position?.vote[0].toLowerCase()),
    };
    return sum;
};

const writeLegislatorVotesFile = (updatedLegislatorVotes: {
    [billid: string]: {
        [legislatorid: string]: string;
    };
}) => {
    const data = {
        united_states: {
            congress: {
                congress: updatedLegislatorVotes,
            },
        },
    };
    const path = `${__dirname}/congress/legislator_votes/index.ts`;
    console.log("WRITING FILE LEGISLAOTR VOTES TO PATH -", path);

    return fs.promises
        .writeFile(path, `export default ${JSON.stringify(data, null, 4)}`)
        .then(() => true)
        .catch(console.error);
};

export const updateLegislatorVotes = (): Promise<boolean | void>[] => {
    return bills.map(
        async (bill: sway.IBill): Promise<boolean | void> => {
            if (!bill.votedate) return false;

            const [month, day, year] = bill.votedate.split("/");
            const voteInfoUrl = getVotesEndpoint(bill.chamber, year, month);

            return fetchVoteDetails(bill, voteInfoUrl)
                .then((vote) => {
                    const legislatorVotesUrl = getVoteEndpoint(
                        vote.roll_call.toString(),
                    );

                    fetchLegislatorVotes(legislatorVotesUrl)
                        .then((votes) => {
                            const updatedLegislatorVotes = {
                                ...currentVotes,
                                [bill.externalId]: legislators.reduce(
                                    (
                                        sum: any,
                                        legislator: sway.IBasicLegislator,
                                    ) =>
                                        matchLegislatorToVote(
                                            sum,
                                            legislator,
                                            votes,
                                        ),
                                    {},
                                ),
                            };
                            return writeLegislatorVotesFile(
                                updatedLegislatorVotes,
                            );
                        })
                        .catch(console.error);
                })
                .catch(console.error);
        },
    );
};
