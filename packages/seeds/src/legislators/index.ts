import SwayFireClient from "@sway/fire";
import { sway } from "sway";

import { BALTIMORE_CITY_LOCALE_NAME, CONGRESS_LOCALE } from "@sway/constants";
import { get } from "lodash";
import { db, firestoreConstructor } from "../firebase";
import SeedLegislatorVotes from "../legislator_votes";
import { ISeedLegislator } from "../types";

import { findFilepath } from "../utils";
import { factoryBaltimoreLegislator } from "./factory";

export default class SeedLegislators {
    fireClient: SwayFireClient;
    locale: sway.ILocale;
    user: sway.IUser;
    constructor(locale: sway.ILocale) {
        this.fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);
        this.locale = locale;
        this.user = { locales: [locale, CONGRESS_LOCALE] } as sway.IUser;
    }

    public seed = async () => {
        return this.getLegislatorsFromFile();
    };

    public createLegislator = async (
        legislator: sway.IBasicLegislator,
        seedLegislatorVotes: SeedLegislatorVotes,
        legislatorVotes: sway.ILegislatorVote[],
    ) => {
        await this.fireClient
            .legislators()
            .ref(legislator.externalId)
            .set({ ...legislator, district: legislator.district || "0" })
            .then(() => seedLegislatorVotes.upsertLegislatorVotes(legislator, legislatorVotes))
            .catch(console.error);
    };

    public updateLegislator = async (
        legislator: sway.IBasicLegislator,
        existing: sway.IBasicLegislator,
        seedLegislatorVotes: SeedLegislatorVotes,
        legislatorVotes: sway.ILegislatorVote[],
    ) => {
        await this.fireClient
            .legislators()
            .ref(legislator.externalId)
            .update({
                ...existing,
                ...legislator,
                district: legislator.district || "0",
            })
            .then(() => seedLegislatorVotes.upsertLegislatorVotes(legislator, legislatorVotes))
            .catch(console.error);
    };

    public getLegislatorsFromFile = async () => {
        const [city, region, country] = this.locale.name.split("-");

        const filepath = await findFilepath(this.locale, "legislators/index.js");
        if (!filepath) {
            console.log(
                "SeedLegislators.getLegislatorsFromFile - no legislators found for filename - legislators/index.js",
            );
            return [];
        } else {
            console.log(
                "SeedLegislators.getLegislatorsFromFile - importing legislators from -",
                filepath,
            );
        }

        const data = await import(filepath).catch((e) => {
            console.error(e);
            return {};
        });

        const imported = get(data, `default.default.${country}.${region}.${city}`) as
            | ISeedLegislator[]
            | { legislators: ISeedLegislator[] };

        const factory = {
            [BALTIMORE_CITY_LOCALE_NAME]: factoryBaltimoreLegislator,
        }[this.locale.name] as (l: ISeedLegislator) => sway.IBasicLegislator;

        if (Array.isArray(imported)) {
            return imported.map(factory);
        } else {
            return imported.legislators.map(factory);
        }
    };

    public getCurrentLegislators = async (): Promise<sway.IBasicLegislator[]> => {
        return this.fireClient
            .legislators()
            .where("active", "==", true)
            .get()
            .then((result) => result.docs.map((r) => r.data()))
            .catch((e) => {
                console.error(e);
                return [];
            });
    };

    public deactivateLegislators = async (
        legislators: sway.IBasicLegislator[],
        current: sway.IBasicLegislator[],
    ) => {
        const newInactive = current.filter((c) => {
            return !legislators.find((l) => l.externalId === c.externalId);
        });

        newInactive.forEach((i) => {
            console.log(
                "seeds.legislators.seedLegislators - deactivate legislator -",
                i.externalId,
            );
            this.fireClient
                .legislators()
                .ref(i.externalId)
                .update({ ...i, active: false })
                .catch(console.error);
        });
    };
}
