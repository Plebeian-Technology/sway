/** @format */

import SwayFireClient from "@sway/fire";
import { sway } from "sway";
import * as seeds from "./src";
import { db, firestore } from "./src/firebase";
import { SEED_UID } from "./src/utils";
import { default as preparer } from "./src/data/united_states/congress/prepareLegislatorFiles";
import { default as updater } from "./src/data/united_states/congress/updateLegislatorVotes";
import { CONGRESS_LOCALE, LOCALES } from "@sway/constants";
import { findLocale } from "@sway/utils";

async function seed() {
    const [
        node, // path to node binary executing file
        file, // path to file being executed (seed.js)
        localeName, // locale name passed into seed.sh as $2
        env, // dotenv_config_path argument
    ] = process.argv;

    if (!localeName) {
        const error = `No localeName received by seed.ts/js. Locale names passed to seed script must be in the form <city>-<region>-<country>. Received: ${localeName}. Exiting without seeding.`;

        console.log(error);
        throw new Error(error);
    }

    if (localeName === "prepare") {
        console.log("Run Propublica Preparer");
        preparer();
        updater();
        return;
    }

    const locale = findLocale(localeName);
    if (!locale) {
        throw new Error(
            `Locale with name - ${localeName} - not in LOCALES. Skipping seeds.`,
        );
    }

    console.log("Creating fireClient client.");
    const fireClient = new SwayFireClient(
        db,
        locale,
        firestore,
    );

    const defaultUser = { locales: [locale, CONGRESS_LOCALE] } as sway.IUser;
    // const user: sway.IUser = seeds.seedUsers(SEED_UID, locale) || defaultUser;

    seeds.seedLegislators(fireClient, locale, defaultUser);
}

seed();
