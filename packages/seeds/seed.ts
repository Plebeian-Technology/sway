/** @format */

import { CONGRESS_LOCALE } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { findLocale, LOCALES_WITHOUT_CONGRESS } from "@sway/utils";
import { sway } from "sway";
import * as seeds from "./src";
import { default as preparer } from "./src/data/united_states/congress/prepareLegislatorFiles";
import { default as updater } from "./src/data/united_states/congress/updateLegislatorVotes";
import { db, firestore } from "./src/firebase";
import { default as sheeter } from "./src/google_sheets";
import { seedLocales } from "./src/locales";
import { default as storager } from "./src/storage";

async function seed() {
    const [
        node, // path to node binary executing file
        file, // path to file being executed (seed.js)
        operation,
        localeName, // locale name passed into seed.sh as $2
        env, // dotenv_config_path argument
    ] = process.argv;

    if (!localeName) {
        const error = `No localeName received by seed.ts/js. Locale names passed to seed script must be in the form <city>-<region>-<country>. Received: ${localeName}. Exiting without seeding.`;

        console.log(error);
        throw new Error(error);
    }

    const locale = findLocale(localeName);
    if (!locale) {
        throw new Error(
            `Locale with name - ${localeName} - not in LOCALES. Skipping seeds.`,
        );
    }

    if (operation === "locales") {
        console.log("Run Seed Locales");
        await seedLocales();
        return;
    }

    if (operation === "prepare") {
        console.log("Run Propublica Preparer");
        preparer();
        updater();
        return;
    }

    if (operation === "storage") {
        console.log("Run storage asset uploader.");
        storager();
        return;
    }

    if (operation === "sheets") {
        console.log("Run Google Sheets runner.");
        sheeter(locale);
        return;
    }

    console.log("Creating fireClient client.");
    const fireClient = new SwayFireClient(db, locale, firestore);

    const defaultUser = { locales: [locale, CONGRESS_LOCALE] } as sway.IUser;

    seeds.seedLegislators(fireClient, locale, defaultUser);
}

seed();
