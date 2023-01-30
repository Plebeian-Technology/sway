/** @format */

import { Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject } from "@sway/utils";
import { flatten, get } from "lodash";
import { sway } from "sway";
import { db, firestoreConstructor } from "../firebase";
import { findFilepath } from "../utils";

interface ILocaleVotes {
    [billFirestoreId: string]: {
        [externalLegislatorId: string]: sway.TLegislatorSupport;
    };
}

export default class SeedLegislatorVotes {
    fireClient: SwayFireClient;
    locale: sway.ILocale;
    constructor(locale: sway.ILocale) {
        this.fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);
        this.locale = locale;
    }

    public seed = async (legislators: sway.IBasicLegislator[], bills: sway.IBill[]) => {
        return this.getLegislatorVotesFromFile(legislators, bills);
    };

    private getLegislatorVotesFromFile = async (
        legislators: sway.IBasicLegislator[],
        bills: sway.IBill[],
    ) => {
        const [city, region, country] = this.locale.name.split("-");

        const filepath = await findFilepath(this.locale, "legislator_votes/index.js");
        if (!filepath) {
            console.log(
                "SeedLegislatorVotes.getLegislatorVotesFromFile - could not find file with data - legislator_votes/index.js",
            );
            return [];
        } else {
            console.log(
                "SeedLegislatorVotes.getLegislatorVotesFromFile - importing legislator_votes from filepath -",
                filepath,
            );
        }

        const data = (await import(filepath)) as
            | sway.ILegislatorVote[]
            | { legislator_votes: sway.ILegislatorVote[] };

        const _votes =
            get(data || {}, `default.default.${country}.${region}.${city}`) ||
            ({} as ILocaleVotes | { legislator_votes: ILocaleVotes });

        const votes = _votes.legislator_votes ? _votes.legislator_votes : _votes;
        if (isEmptyObject(votes)) {
            return [];
        }

        return flatten(
            legislators.map((legislator: sway.IBasicLegislator) => {
                return this.getVotesAsLegislatorVotes(legislator, bills, votes as ILocaleVotes);
            }),
        );
    };

    private getVotesAsLegislatorVotes = (
        legislator: sway.IBasicLegislator,
        bills: sway.IBill[],
        votes: ILocaleVotes,
    ): sway.ILegislatorVote[] => {
        console.log("Generating Legislator Votes");
        if (legislator.externalId.includes("2016")) return [];

        return bills
            .map((bill) => {
                const support = votes[bill.firestoreId][legislator.externalId];
                if (support) {
                    return {
                        externalLegislatorId: legislator.externalId,
                        billFirestoreId: bill.firestoreId,
                        support,
                    };
                } else {
                    return null;
                }
            })
            .filter(Boolean) as sway.ILegislatorVote[];
    };

    public upsertLegislatorVotes = (
        legislator: sway.IBasicLegislator,
        legislatorVotes: sway.ILegislatorVote[],
    ) => {
        const votes = legislatorVotes.filter(
            (legVote: sway.ILegislatorVote) =>
                legVote.externalLegislatorId === legislator.externalId,
        );

        votes.forEach(async (vote: sway.ILegislatorVote) => {
            await this.createLegislatorVote(
                vote.billFirestoreId,
                vote.externalLegislatorId,
                vote.support,
            ).catch(console.error);
        });
    };

    private createLegislatorVote = async (
        billFirestoreId: string,
        externalLegislatorId: string,
        support: sway.TLegislatorSupport,
    ): Promise<sway.ILegislatorVote | void> => {
        if (!this.isSupportable(support)) {
            return;
        }

        const existing = await this.fireClient
            .legislatorVotes()
            .get(externalLegislatorId, billFirestoreId);
        if (!existing || isEmptyObject(existing)) {
            return this.fireClient
                .legislatorVotes()
                .create(externalLegislatorId, billFirestoreId, support);
        } else {
            return this.updateLegislatorVote(billFirestoreId, externalLegislatorId, support);
        }
    };

    private updateLegislatorVote = (
        billFirestoreId: string,
        externalLegislatorId: string,
        support: sway.TLegislatorSupport,
    ) => {
        if (!support || !this.isSupportable(support)) {
            return this.fireClient
                .legislatorVotes()
                .updateSupport(externalLegislatorId, billFirestoreId, support)
                .catch(console.error);
        }
    };

    private isSupportable = (support: sway.TLegislatorSupport): boolean => {
        if (!support) return false;
        return [Support.For, Support.Against, Support.Abstain].includes(support);
    };
}
