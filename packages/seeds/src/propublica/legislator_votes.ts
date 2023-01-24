import { CONGRESS, CONGRESS_LOCALE, Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { flatten, get } from "lodash";
import { sway } from "sway";
import billsData from "../data/united_states/congress/congress/bills";
import legislatorsData from "../data/united_states/congress/congress/legislators";
import { db as firebase, firestoreConstructor } from "../firebase";
import { PROPUBLICA_API_BASE_ROUTE, PROPUBLICA_HEADERS } from "./constants";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

export default class PropublicaLegislatorVotes {
    bills: sway.IBill[];
    legislators: sway.IBasicLegislator[];
    constructor() {
        this.bills = billsData.united_states.congress.congress as sway.IBill[];
        this.legislators = legislatorsData.united_states.congress.congress
            .legislators as sway.IBasicLegislator[];
    }

    private fetchVoteDetails = (bill: sway.IBill, endpoint: string) => {
        return this.getJSON(endpoint).then((result: any) => {
            if (!result) {
                console.log(
                    `PropublicaLegislatorVotes.fetchVoteDetails - no votes returned for bill - ${bill.externalId} - from propublica endpoint -`,
                    endpoint,
                );
                return null;
            }

            const votes: any[] = result.results.votes;

            const func = bill.externalId.startsWith("speaker")
                ? (v: any) => {
                      // Corner case for speaker vote in 118th Congress, starting in January 2023
                      if (v.congress === 118) {
                          return v.roll_call === 20;
                      }
                  }
                : (v: any) => v.bill_id === bill.externalId || v?.bill?.bill_id === bill.externalId;

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
}
