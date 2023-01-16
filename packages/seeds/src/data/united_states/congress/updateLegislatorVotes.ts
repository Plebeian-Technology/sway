import { Support, CONGRESS } from "@sway/constants";
import * as fs from "fs/promises";
import { flatten, get } from "lodash";
import { sway } from "sway";
import billsData from "./congress/bills";
import legislatorsData from "./congress/legislators";
import * as path from "path";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

// eslint-disable-next-line
// const xml2js = require("xml2js");
// const xmlParser = xml2js.Parser();

const PROPUBLICA_HEADERS = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "X-API-Key": process.env.PROPUBLICA_API_KEY || "",
};

interface ISwayLegislatorVote {
    [billExternalId: string]: {
        [legislatorExternalId: string]: "for" | "against" | "abstain" | null;
    };
}
// interface ICongressDotGovVote {
//     legislator: [
//         {
//             _: string;
//             $: {
//                 "name-id": string;
//                 "sort-field": string;
//                 "unaccented-name": string;
//                 party: "R" | "D" | "I";
//                 state: string;
//                 role: "legislator";
//             };
//         },
//     ];
//     vote: [string];
// }

interface IPropublicaVote {
    member_id: string;
    name: string;
    party: string;
    state: string;
    vote_position: "Yes" | "No" | "Not Voting";
    dw_nominate: number;
}

const bills = billsData.united_states.congress.congress as sway.IBill[];
const legislators = legislatorsData.united_states.congress.congress
    .legislators as sway.IBasicLegislator[];
// const currentVotes = legislatorVotes.united_states.congress.congress as {
//     [billid: string]: {
//         [legislatorExternalId: string]: string;
//     };
// };

// 1 or 2, depending on year (1 is odd-numbered years, 2 is even-numbered years)
const congressionalSession = () => {
    const date = new Date();
    const year = date.getFullYear();
    return year % 2 === 0 ? 2 : 1;
};

const getVotesEndpoint = (bill: sway.IBill) => {
    if (bill.chamber === "both") {
        return ["house", "senate"].map((chamber: string) => {
            const [month, , year] = bill[`${chamber}VoteDate`].split("/");
            return `https://api.propublica.org/congress/v1/${chamber}/votes/${year}/${month}.json`;
        });
    } else {
        const [month, , year] = bill[`${bill.chamber}VoteDate`].split("/");
        return [
            `https://api.propublica.org/congress/v1/${bill.chamber}/votes/${year}/${month}.json`,
        ];
    }
};

const getVoteEndpoint = (chamber: string, rollCall: string, congress?: number) => {
    const session = congressionalSession();
    return `https://api.propublica.org/congress/v1/${
        congress || CONGRESS
    }/${chamber}/sessions/${session}/votes/${rollCall}.json`;
};
// const getCongressDotGovHouseVoteEndpoint = (rollCall: string) => {
//     while (rollCall.length < 3) {
//         rollCall = "0" + rollCall;
//     }
//     const year = new Date().getFullYear();
//     return `https://clerk.house.gov/evs/${year}/roll${rollCall}.xml`;
// };

const getJSON = (url: string) => {
    console.log("FETCHING -", url);

    return fetch(url, { headers: PROPUBLICA_HEADERS })
        .then((res) => res.json())
        .catch(console.error);
};

// const getXML = (url: string) => {
//     console.log("FETCHING XML -", url);

//     return fetch(url)
//         .then((res) => res.text())
//         .catch(console.error);
// };

const toSwaySupport = (billExternalId: string, position: string) => {
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

    if (billExternalId.startsWith("speaker") && billExternalId.split("-").last() === "118") {
        if (position === "mccarthy") return Support.For;
        if (position === "jeffries") return Support.Against;
    }

    throw new Error(`POSITION WAS - ${position}`);
};

const fetchVoteDetails = (bill: sway.IBill, endpoint: string) => {
    return getJSON(endpoint).then((result: any) => {
        const votes: any[] = result.results.votes;

        const func = bill.externalId.startsWith("speaker")
            ? (v: any) => {
                  if (v.congress === 118) {
                      return v.roll_call === 20;
                  }
              }
            : (v: any) => v.bill_id === bill.externalId || v?.bill?.bill_id === bill.externalId;

        const vote = votes.find(func);
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

// const fetchCongressDotGovLegislatorVotes = (endpoint: string) => {
//     return getXML(endpoint).then((result: any) => {
//         return xmlParser.parseStringPromise(result).then((res: any) => {
//             return get(res, "rollcall-vote.vote-data.0.recorded-vote");
//         });
//     });
// };

const fetchPropublicaLegislatorVote = (endpoint: string) => {
    return getJSON(endpoint).then((result) => {
        return get(result, "results.votes.vote.positions");
    });
};

// const findCongressDotGovLegislatorPosition = (
//     vote: ICongressDotGovVote,
//     legislator: sway.IBasicLegislator,
// ) => {
//     return get(vote, "legislator.0.$.name-id") === legislator.externalId;
// };

const findPropublicaLegislatorPosition = (
    vote: IPropublicaVote,
    legislator: sway.IBasicLegislator,
) => {
    return get(vote, "member_id") === legislator.externalId;
};

const matchLegislatorToPropublicaVote = (
    billExternalId: string,
    legislator: sway.IBasicLegislator,
    votes: IPropublicaVote[],
): { [externalId: string]: "for" | "against" | "abstain" | null } | undefined => {
    const position: IPropublicaVote | undefined = votes.find((vote: IPropublicaVote) =>
        findPropublicaLegislatorPosition(vote, legislator),
    );
    if (!position) {
        // console.log("NO VOTE FOR LEGISLATOR", legislator.externalId);
        return {
            [legislator.externalId]: null,
        };
    }
    // console.log(
    //     "ADDING LEGISLATOR SUPPORT",
    //     legislator.externalId,
    //     toSwaySupport(billExternalId, position?.vote_position?.toLowerCase()),
    // );
    return {
        [legislator.externalId]: toSwaySupport(
            billExternalId,
            position?.vote_position?.toLowerCase(),
        ),
    };
};

// const matchCongressDotGovLegislatorToVote = (
//     legislator: sway.IBasicLegislator,
//     votes: ICongressDotGovVote[],
// ) => {
//     const position: ICongressDotGovVote | undefined = votes.find((vote: ICongressDotGovVote) =>
//         findCongressDotGovLegislatorPosition(vote, legislator),
//     );
//     if (!position) {
//         console.log("NO VOTE FOR LEGISLATOR", legislator.externalId);
//         return {};
//     }
//     console.log(
//         "ADDING LEGISLATOR SUPPORT",
//         legislator.externalId,
//         toSwaySupport(position?.vote[0].toLowerCase()),
//     );
//     return {
//         [legislator.externalId]: toSwaySupport(position?.vote[0].toLowerCase()),
//     };
// };

const writeLegislatorVotesFile = (updatedLegislatorVotes: ISwayLegislatorVote) => {
    const root = path.resolve(__dirname).replace("/dist", "");
    const dir = `${root}/congress/legislator_votes`;

    const data = {
        united_states: {
            congress: {
                congress: updatedLegislatorVotes,
            },
        },
    };
    const filepath = `${dir}/index.ts`;
    console.log("WRITING FILE LEGISLAOTR VOTES TO PATH -", { filepath, dir, data });

    return fs
        .stat(filepath)
        .then(() => {
            return fs.truncate(filepath, 0).then(() => {
                return fs
                    .writeFile(filepath, `export default ${JSON.stringify(data)}`)
                    .then(() => true)
                    .catch(console.error);
            });
        })
        .catch(() => {
            return fs
                .writeFile(filepath, `export default ${JSON.stringify(data)}`)
                .then(() => true)
                .catch(console.error);
        });
};

export default async () => {
    const _updatedLegislatorVotes = bills.map(async (bill: sway.IBill) => {
        const billCongress = bill.externalId.split("-").last();
        if (Number(billCongress) !== CONGRESS) {
            console.log("SKIPPING BILL, BILL CONGRESS DOES NOT MATCH CURRENT CONGRESS", {
                externalId: bill.externalId,
                CONGRESS,
                billCongress: Number(billCongress),
            });
            return;
        }

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
        console.log("VOTE INFO URLS - ", bill.externalId, voteInfoUrls);

        const details = await Promise.all(
            voteInfoUrls.map(async (voteInfoUrl) => {
                return fetchVoteDetails(bill, voteInfoUrl);
            }),
        );
        // console.log("VOTES DETAILS FOR BILL -", bill.externalId);
        // console.dir(details, { depth: null });

        // @ts-ignore
        const _votes = (await Promise.all(
            details.map(async (vote) => {
                if (!vote) return;

                const legislatorVotesUrl = getVoteEndpoint(
                    vote.chamber.toLowerCase(),
                    vote.roll_call.toString(),
                    vote.congress,
                );
                console.log("VOTE URL FOR BILL -", bill.externalId, legislatorVotesUrl);
                return fetchPropublicaLegislatorVote(legislatorVotesUrl);
                // return fetchLegislatorVotes(legislatorVotesUrl);
            }),
        )) as IPropublicaVote[];

        // console.log("REDUCING VOTES FOR BILL -", bill.externalId);
        // console.dir(_votes, { depth: null });

        const votes = flatten(_votes).filter(Boolean);

        return {
            [bill.externalId]: legislators.reduce(
                (
                    sum: { [externalId: string]: "for" | "against" | "abstain" | null },
                    legislator: sway.IBasicLegislator,
                ) => {
                    // const obj = matchCongressDotGovLegislatorToVote(legislator, votes);
                    const obj = matchLegislatorToPropublicaVote(bill.externalId, legislator, votes);
                    if (!obj) {
                        return sum;
                    } else {
                        return {
                            ...sum,
                            ...obj,
                        };
                    }
                },
                {},
            ),
        };
    });

    const updatedLegislatorVotes = await Promise.all(_updatedLegislatorVotes)
        .then((results) => {
            // console.log("REDUCING RESULTS");
            // if (!results) {
            //     console.log("no results, skipping");
            // }
            // console.dir(results, { depth: null });

            return results.filter(Boolean).reduce((sum: any, item?: ISwayLegislatorVote) => {
                if (!item) return sum;

                return {
                    ...sum,
                    ...item,
                };
            }, {} as ISwayLegislatorVote);
        })
        .catch(console.error);
    return writeLegislatorVotesFile(updatedLegislatorVotes);
};
