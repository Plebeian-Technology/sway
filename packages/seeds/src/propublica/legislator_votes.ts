import { CONGRESS, CONGRESS_LOCALE, Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject, logDev } from "@sway/utils";
import { get } from "lodash";
import { sway } from "sway";
import billsData from "../data/united_states/congress/congress/bills";
import legislatorsData from "../data/united_states/congress/congress/legislators";
import { db, db as firebase, firestoreConstructor } from "../firebase";
import { writeDataToFile } from "../utils";
import { PROPUBLICA_API_BASE_ROUTE, PROPUBLICA_HEADERS } from "./constants";
import PropublicaLegislatorVote from "./legislator_vote";
import { propublica } from "./types";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

export default class PropublicaLegislatorVotes {
    fireClient: SwayFireClient;
    bills: sway.IBill[];
    legislators: sway.IBasicLegislator[];
    constructor() {
        this.fireClient = new SwayFireClient(db, CONGRESS_LOCALE, firestoreConstructor, console);
        this.bills = billsData.united_states.congress.congress as sway.IBill[];
        this.legislators = legislatorsData.united_states.congress.congress
            .legislators as sway.IBasicLegislator[];
    }

    /**
     *
     * Create/update congressional legislator votes
     *
     */

    public createLegislatorVotes = async () => {
        const votes = await this.getLegislatorVotes();
        votes.forEach((vote: propublica.IDataFileLegislatorVote) => {
            const billFirestoreId = Object.keys(vote).first();
            const positions = vote[billFirestoreId];
            const legislatorIds = Object.keys(positions);

            legislatorIds.forEach(async (externalLegislatorId: string) => {
                const position = positions[externalLegislatorId];
                if (this.isSupportable(position)) {
                    await this.upsertLegislatorVote(
                        billFirestoreId,
                        externalLegislatorId,
                        position,
                    );
                }
            });
        });
    };

    private upsertLegislatorVote = async (
        billFirestoreId: string,
        externalLegislatorId: string,
        support: sway.TLegislatorSupport,
    ) => {
        const existing = await this.fireClient
            .legislatorVotes()
            .get(externalLegislatorId, billFirestoreId);

        if (!existing || isEmptyObject(existing)) {
            return this.createLegislatorVote(billFirestoreId, externalLegislatorId, support);
        } else {
            return this.updateLegislatorVote(
                billFirestoreId,
                externalLegislatorId,
                support,
                existing,
            );
        }
    };

    private createLegislatorVote = async (
        billFirestoreId: string,
        externalLegislatorId: string,
        support: sway.TLegislatorSupport,
    ) => {
        return this.fireClient
            .legislatorVotes()
            .create(externalLegislatorId, billFirestoreId, support);
    };

    private updateLegislatorVote = async (
        billFirestoreId: string,
        externalLegislatorId: string,
        newSupport: sway.TLegislatorSupport,
        existing: sway.ILegislatorVote,
    ) => {
        const existingSupport = existing.support;
        if (!existingSupport || !this.isSupportable(existingSupport)) {
            return this.fireClient
                .legislatorVotes()
                .updateSupport(externalLegislatorId, billFirestoreId, newSupport)
                .catch(console.error);
        }
    };

    private isSupportable = (support: sway.TLegislatorSupport): boolean => {
        if (!support) return false;
        return [Support.For, Support.Against, Support.Abstain].includes(support);
    };

    /**
     *
     * Get congressional legislator votes from Propublica
     *
     */

    public getLegislatorVotes = async (): Promise<propublica.IDataFileLegislatorVote[]> => {
        if (isEmptyObject(this.bills)) {
            console.error(
                "PropublicaLegislatorVotes.getLegislatorVotes - bills from src/data/united_states/congress/congress/bills are empty.",
            );
            return [];
        }
        if (isEmptyObject(this.legislators)) {
            console.error(
                "PropublicaLegislatorVotes.getLegislatorVotes - bills from src/data/united_states/congress/congress/legislators are empty.",
            );
            return [];
        }

        const votes = await Promise.all(
            this.bills.map(
                async (bill: sway.IBill): Promise<propublica.IDataFileLegislatorVote> => {
                    const billCongress = bill.externalId.split("-").last();
                    logDev(
                        `PropublicaLegislatorVotes.getLegislatorVotes - bill ${bill.externalId} - billCongress - ${billCongress}.`,
                    );

                    if (Number(billCongress) !== CONGRESS) {
                        return this.deactivateBillFromPastCongress(bill, billCongress);
                    }

                    if (!bill.votedate) {
                        logDev(
                            `PropublicaLegislatorVotes.getLegislatorVotes - bill ${bill.externalId} - has note votedate. Skip getting votes.`,
                        );
                        return { [bill.externalId]: {} };
                    }

                    const voteURLs = this.getVotesEndpoint(bill);

                    const voteDetails = (await Promise.all(
                        voteURLs.map((url) => this.fetchVoteDetails(bill, url)),
                    )) as propublica.IVote[];

                    const positions = await voteDetails.reduce(async (sum, vote) => {
                        if (!vote) return sum;

                        const votePositionsURL = this.getVoteEndpoint(
                            vote.chamber.toLowerCase(),
                            vote.roll_call.toString(),
                            vote.congress,
                        );

                        const votePositions = await this.fetchPropublicaLegislatorVote(
                            votePositionsURL,
                        );

                        return {
                            ...sum,
                            [vote.bill.bill_id]: votePositions.reduce(
                                (sumPositions, position) => ({
                                    ...sumPositions,
                                    [position.member_id]: new PropublicaLegislatorVote(position),
                                }),
                                {} as Record<string, PropublicaLegislatorVote>,
                            ),
                        };
                    }, {} as Promise<Record<string, Record<string, PropublicaLegislatorVote>>>);

                    return {
                        [bill.externalId]: this.legislators.reduce(
                            (
                                sum: { [externalId: string]: sway.TLegislatorSupport | null },
                                legislator: sway.IBasicLegislator,
                            ) => {
                                // const obj = matchCongressDotGovLegislatorToVote(legislator, votes);
                                const legislatorVote =
                                    positions[bill.externalId][legislator.externalId];
                                if (!legislatorVote) {
                                    return sum;
                                } else {
                                    return {
                                        ...sum,
                                        [legislator.externalId]: legislatorVote.toSwaySupport(
                                            bill.externalId,
                                        ),
                                    };
                                }
                            },
                            {},
                        ),
                    };
                },
            ),
        );

        await this.writeLegislatorVotesFile(votes);
        return votes;
    };

    private writeLegislatorVotesFile = async (votes: propublica.IDataFileLegislatorVote[]) => {
        const data = votes.reduce((sum, vote) => ({ ...sum, ...vote }), {});
        await writeDataToFile(CONGRESS_LOCALE, "legislator_votes", data).catch(console.error);
    };

    private fetchVoteDetails = (
        bill: sway.IBill,
        endpoint: string,
    ): Promise<propublica.IVote | null> => {
        return this.getJSON(endpoint).then((result: any) => {
            if (!result) {
                console.log(
                    `PropublicaLegislatorVotes.fetchVoteDetails - no votes returned for bill - ${bill.externalId} - from propublica endpoint -`,
                    endpoint,
                );
                return null;
            }

            const votes = result.results.votes as propublica.IVote[];

            const func = bill.externalId.startsWith("speaker")
                ? (v: propublica.IVote) => {
                      // Corner case for speaker vote in 118th Congress, starting in January 2023
                      if (v.congress === 118) {
                          return v.roll_call === 20;
                      }
                  }
                : (v: propublica.IVote) => v?.bill?.bill_id === bill.externalId;

            const vote = votes.find(func);
            if (!vote) {
                console.log(
                    `PropublicaLegislatorVotes.fetchVoteDetails - could not find vote for bill - ${bill.externalId} - from propublica endpoint -`,
                    endpoint,
                );

                console.dir(votes, { depth: null });
                return null;
            }
            return vote;
        });
    };

    private fetchPropublicaLegislatorVote = (
        endpoint: string,
    ): Promise<propublica.ILegislatorVote[]> => {
        return this.getJSON(endpoint)
            .then((result) => {
                return (get(result, "results.votes.vote.positions") ||
                    []) as propublica.ILegislatorVote[];
            })
            .catch((e) => {
                console.error(e);
                return [];
            });
    };

    private getVotesEndpoint = (bill: sway.IBill) => {
        if (bill.chamber === "both") {
            return ["house", "senate"].map((chamber: string) => {
                const [month, , year] = bill[`${chamber}VoteDate`].split("/");
                return `${PROPUBLICA_API_BASE_ROUTE}/${chamber}/votes/${year}/${month}.json`;
            });
        } else {
            const [month, , year] = bill[`${bill.chamber}VoteDate`].split("/");
            return [`${PROPUBLICA_API_BASE_ROUTE}/${bill.chamber}/votes/${year}/${month}.json`];
        }
    };

    private getVoteEndpoint = (chamber: string, rollCall: string, congress?: number) => {
        const session = this.getCongressionalSession();
        return `${PROPUBLICA_API_BASE_ROUTE}/${
            congress || CONGRESS
        }/${chamber}/sessions/${session}/votes/${rollCall}.json`;
    };

    /**
     * 1 or 2, depending on year (1 is odd-numbered years, 2 is even-numbered years)
     *
     * @returns 1 or 2
     */
    private getCongressionalSession = (): 1 | 2 => {
        const date = new Date();
        const year = date.getFullYear();
        return year % 2 === 0 ? 2 : 1;
    };

    private getJSON = (url: string) => {
        console.log("PropublicaLegislatorVotes.getJSON.url -", url);

        return fetch(url, { headers: PROPUBLICA_HEADERS })
            .then((res) => res.json())
            .catch(console.error);
    };

    private deactivateBillFromPastCongress = async (
        bill: sway.IBill,
        billCongress: number | string,
    ) => {
        console.log(
            `PropublicaLegislatorVotes.deactivateBillFromPastCongress - bill ${bill.externalId} - has old congress - ${billCongress}. De-activating.`,
            {
                externalId: bill.externalId,
                CONGRESS,
                billCongress: Number(billCongress),
            },
        );
        const ref = new SwayFireClient(firebase, CONGRESS_LOCALE, firestoreConstructor)
            .bills()
            .ref(bill.externalId);

        if (ref) {
            await ref
                .update({
                    ...bill,
                    active: false,
                })
                .catch(console.error);
        }
        return { [bill.externalId]: {} };
    };
}
