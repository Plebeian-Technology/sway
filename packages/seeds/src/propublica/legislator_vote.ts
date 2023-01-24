import { CONGRESS, CONGRESS_LOCALE, Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { flatten, get } from "lodash";
import { sway } from "sway";
import billsData from "../data/united_states/congress/congress/bills";
import legislatorsData from "../data/united_states/congress/congress/legislators";
import { db as firebase, firestoreConstructor } from "../firebase";
import { PROPUBLICA_API_BASE_ROUTE, PROPUBLICA_HEADERS } from "./constants";
import { writeDataToFile } from "./utils";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

export default class PropublicaLegislatorVote {
    private fetchPropublicaLegislatorVote = (endpoint: string) => {
        return this.getJSON(endpoint).then((result) => {
            return get(result, "results.votes.vote.positions");
        });
    };

    private findPropublicaLegislatorPosition = (
        vote: propublica.ILegislatorVote,
        legislator: sway.IBasicLegislator,
    ) => {
        return (
            (get(vote, "member_id") || "").toUpperCase() ===
            (legislator?.externalId || "").toUpperCase()
        );
    };

    private writeLegislatorVotesFile = async (
        updatedLegislatorVotes: propublica.IDataFileLegislatorVote,
    ) => {
        const data = {
            united_states: {
                congress: {
                    congress: {
                        legislator_votes: updatedLegislatorVotes,
                    },
                },
            },
        };

        await writeDataToFile(CONGRESS_LOCALE, data).catch(console.error);
    };

    private matchLegislatorToPropublicaVote = (
        billExternalId: string,
        legislator: sway.IBasicLegislator,
        votes: propublica.ILegislatorVote[],
    ): { [externalId: string]: "for" | "against" | "abstain" | null } | undefined => {
        const position: propublica.ILegislatorVote | undefined = votes.find(
            (vote: propublica.ILegislatorVote) =>
                this.findPropublicaLegislatorPosition(vote, legislator),
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
            [legislator.externalId]: this.toSwaySupport(
                billExternalId,
                position?.vote_position?.toLowerCase(),
            ),
        };
    };

    private toSwaySupport = (billExternalId: string, position: string) => {
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

        throw new Error(
            `PropublicaLegislatorVotes.toSwaySupport received an unexpected 'position' argument - ${position}`,
        );
    };

    private getJSON = (url: string) => {
        console.log("PropublicaLegislatorVote.getJSON.url -", url);

        return fetch(url, { headers: PROPUBLICA_HEADERS })
            .then((res) => res.json())
            .catch(console.error);
    };
}
