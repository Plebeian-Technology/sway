import * as fs from "fs";
import fetch, { Response } from "node-fetch";
import { Support } from "@sway/constants";
import { sway } from "sway";
import billsData from "./congress/bills";
import legislatorsData from "./congress/legislators";
import legislatorVotes from "./congress/legislator_votes";
import { flatten, get } from "lodash";

const xml2js = require("xml2js");
const xmlParser = xml2js.Parser();

const CONGRESS = 117;

const PROPUBLICA_HEADERS = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "X-API-Key": process.env.PROPUBLICA_API_KEY || "",
};

interface ISwayLegislatorVote {
    [billid: string]: {
        [legislatorid: string]: string;
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

interface IPropublicaVote {
    member_id: string;
    name: string;
    party: string;
    state: string;
    vote_position: "Yes" | "No" | "Not Voting";
    dw_nominate: number;
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

const getVotesEndpoint = (bill: sway.IBill) => {
    if (bill.chamber === "both") {
        return ["house", "senate"].map((chamber: string) => {
            const [month, day, year] = bill[`${chamber}VoteDate`].split("/");
            return `https://api.propublica.org/congress/v1/${chamber}/votes/${year}/${month}.json`;
        });
    } else {
        const [month, day, year] = bill[`${bill.chamber}VoteDate`].split("/");
        return [
            `https://api.propublica.org/congress/v1/${bill.chamber}/votes/${year}/${month}.json`,
        ];
    }
};

const getVoteEndpoint = (chamber: string, rollCall: string) => {
    const session = congressionalSession();

    return `https://api.propublica.org/congress/v1/${CONGRESS}/${chamber}/sessions/${session}/votes/${rollCall}.json`;
};
const getCongressDotGovHouseVoteEndpoint = (rollCall: string) => {
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
    if (position === "yes") return Support.For;
    if (position === "nay") return Support.Against;
    if (position === "no") return Support.Against;
    if (position === "not voting") return Support.Abstain;
    if (position === "abstain") return Support.Abstain;
    if (position === "did not vote") return Support.Abstain;
    if (position === "present") return Support.Abstain;

    // * By tradition, the Speaker of the House rarely votes.
    // * When the Speaker does not vote, the original data provided the Clerk of the House contains no record for the Speaker on that vote.
    // * In those cases, the API records the Speaker’s voting position as Speaker, and it is not included in the vote total calculations.
    if (position === "speaker") return Support.Abstain;
    throw new Error(`POSITION WAS - ${position}`);
};

const fetchVoteDetails = (bill: sway.IBill, endpoint: string) => {
    return getJSON(endpoint).then((result: any) => {
        const votes: any[] = result.results.votes;
        const vote = votes.find(
            (v: any) =>
                v.bill_id === bill.externalId ||
                v?.bill?.bill_id === bill.externalId,
        );
        if (!vote) {
            console.log(
                `COULD NOT FIND VOTE FOR BILL - ${bill.externalId} - in VOTES from PROPUBLICA -`,
                endpoint,
            );

            console.dir(votes, { depth: null });
            return null;
        }
        return vote;
    });
};

const fetchCongressDotGovLegislatorVotes = (endpoint: string) => {
    return getXML(endpoint).then((result: any) => {
        return xmlParser.parseStringPromise(result).then((res: any) => {
            return get(res, "rollcall-vote.vote-data.0.recorded-vote");
        });
    });
};

const fetchPropublicaLegislatorVote = (endpoint: string) => {
    return getJSON(endpoint).then((result) => {
        return get(result, "results.votes.vote.positions");
    });
};

const findCongressDotGovLegislatorPosition = (
    vote: ICongressDotGovVote,
    legislator: sway.IBasicLegislator,
) => {
    return get(vote, "legislator.0.$.name-id") === legislator.externalId;
};

const findPropublicaLegislatorPosition = (
    vote: IPropublicaVote,
    legislator: sway.IBasicLegislator,
) => {
    return get(vote, "member_id") === legislator.externalId;
};

const matchLegislatorToPropublicaVote = (
    legislator: sway.IBasicLegislator,
    votes: IPropublicaVote[],
) => {
    const position: IPropublicaVote | undefined = votes.find(
        (vote: IPropublicaVote) =>
            findPropublicaLegislatorPosition(vote, legislator),
    );
    if (!position) {
        console.log("NO VOTE FOR LEGISLATOR", legislator.externalId);
        return {};
    }
    console.log(
        "ADDING LEGISLATOR SUPPORT",
        legislator.externalId,
        toSwaySupport(position?.vote_position?.toLowerCase()),
    );
    return {
        [legislator.externalId]: toSwaySupport(
            position?.vote_position?.toLowerCase(),
        ),
    };
};

const matchCongressDotGovLegislatorToVote = (
    legislator: sway.IBasicLegislator,
    votes: ICongressDotGovVote[],
) => {
    const position: ICongressDotGovVote | undefined = votes.find(
        (vote: ICongressDotGovVote) =>
            findCongressDotGovLegislatorPosition(vote, legislator),
    );
    if (!position) {
        console.log("NO VOTE FOR LEGISLATOR", legislator.externalId);
        return {};
    }
    console.log(
        "ADDING LEGISLATOR SUPPORT",
        legislator.externalId,
        toSwaySupport(position?.vote[0].toLowerCase()),
    );
    return {
        [legislator.externalId]: toSwaySupport(position?.vote[0].toLowerCase()),
    };
};

const writeLegislatorVotesFile = (
    updatedLegislatorVotes: ISwayLegislatorVote,
) => {
    const data = {
        united_states: {
            congress: {
                congress: updatedLegislatorVotes,
            },
        },
    };
    const path = `${__dirname}/congress/legislator_votes/index.ts`;
    console.log("WRITING FILE LEGISLAOTR VOTES TO PATH -", path, data);

    return fs.promises
        .stat(path)
        .then(() => {
            return fs.promises.truncate(path, 0).then(() => {
                return fs.promises
                    .writeFile(path, `export default ${JSON.stringify(data)}`)
                    .then(() => true)
                    .catch(console.error);
            });
        })
        .catch(() => {
            return fs.promises
                .writeFile(path, `export default ${JSON.stringify(data)}`)
                .then(() => true)
                .catch(console.error);
        });
};

export default async () => {
    const _updatedLegislatorVotes = bills.map(async (bill: sway.IBill) => {
        console.log("UPDATING BILL - ", bill.externalId);

        if (!bill.votedate) return;
        // if (
        //     currentVotes[bill.externalId] &&
        //     Object.keys(currentVotes[bill.externalId]).length > 500
        // ) {
        //     console.log(
        //         `Legislator votes for bill - ${bill.externalId} - has already been seeded. Skipping.`,
        //     );
        //     return;
        // }

        const voteInfoUrls = getVotesEndpoint(bill);
        console.log("VOTE INFO URLS - ", voteInfoUrls);

        const details = await Promise.all(
            voteInfoUrls.map(async (voteInfoUrl) => {
                return fetchVoteDetails(bill, voteInfoUrl);
            }),
        );
        console.log("VOTES DETAILS FOR BILL -", bill.externalId);
        console.dir(details, { depth: null });

        const _votes = await Promise.all(
            details.map(async (vote) => {
                if (!vote) return;

                const legislatorVotesUrl = getVoteEndpoint(
                    vote.chamber.toLowerCase(),
                    vote.roll_call.toString(),
                );
                return fetchPropublicaLegislatorVote(legislatorVotesUrl);
                // return fetchLegislatorVotes(legislatorVotesUrl);
            }),
        );

        console.log("REDUCING VOTES FOR BILL -", bill.externalId);
        console.dir(_votes, { depth: null });

        const votes = flatten(_votes).filter(Boolean);

        return {
            [bill.externalId]: legislators.reduce(
                (sum: any, legislator: sway.IBasicLegislator) => {
                    // const obj = matchCongressDotGovLegislatorToVote(legislator, votes);
                    const obj = matchLegislatorToPropublicaVote(
                        legislator,
                        votes,
                    );
                    sum = {
                        ...sum,
                        ...obj,
                    };
                    return sum;
                },
                {},
            ),
        };
    });

    const updatedLegislatorVotes = Promise.all(_updatedLegislatorVotes).then(
        (results) => {
            console.log("REDUCING RESULTS");
            if (!results) {
                console.log("no results, skipping");
            }
            console.dir(results, { depth: null });

            return results.reduce((sum: any, item: any) => {
                if (!item) return sum;

                return {
                    ...sum,
                    ...item,
                };
            }, {});
        },
    );
    updatedLegislatorVotes.then((votes) => {
        console.log("WRITING VOTES TO FILE");
        console.dir(votes, { depth: null });
        return writeLegislatorVotesFile(votes);
    });
};
