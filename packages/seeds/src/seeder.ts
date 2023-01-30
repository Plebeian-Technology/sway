import SwayFireClient from "@sway/fire";
import { sway } from "sway";

import { CONGRESS_LOCALE } from "@sway/constants";
import SeedBills from "./bills";
import { db, firestoreConstructor } from "./firebase";

import SeedLegislators from "./legislators";
import SeedLegislatorVotes from "./legislator_votes";
import SeedOrganizations from "./organizations";

export default class Seeder {
    fireClient: SwayFireClient;
    locale: sway.ILocale;
    user: sway.IUser;
    constructor(locale: sway.ILocale) {
        this.fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);
        this.locale = locale;
        this.user = { locales: [locale, CONGRESS_LOCALE] } as sway.IUser;
    }

    public seed = async () => {
        const seedLegislators = new SeedLegislators(this.locale);
        const legislators = await seedLegislators.getLegislatorsFromFile();

        const bills = await new SeedBills(this.locale).seed();
        const _organizations = await new SeedOrganizations(this.locale).seed();

        const seedLegislatorVotes = new SeedLegislatorVotes(this.locale);
        const legislatorVotes = await seedLegislatorVotes.seed(legislators, bills);

        if (!Array.isArray(legislators)) {
            console.log("Legislators is NOT an array. Skip seeding legislators.");
            return [];
        }

        const currentLegislators = await seedLegislators.getCurrentLegislators();

        await seedLegislators.deactivateLegislators(legislators, currentLegislators);

        legislators.forEach(async (legislator: sway.IBasicLegislator) => {
            const existing = currentLegislators.find((l) => l.externalId === legislator.externalId);
            if (existing) {
                await seedLegislators.updateLegislator(
                    legislator,
                    existing,
                    seedLegislatorVotes,
                    legislatorVotes,
                );
            } else {
                await seedLegislators.createLegislator(
                    legislator,
                    seedLegislatorVotes,
                    legislatorVotes,
                );
            }
        });

        return legislators;
    };
}
