/** @format */

import { CONGRESS_LOCALE } from "src/constants";
import SwayFireClient from "src/fire";
import { findLocale } from "src/utils";
import { sway } from "sway";
import { seedLegislators } from "./legislators";
import { default as preparer } from "./data/united_states/congress/prepareLegislatorFiles";
import { default as updater } from "./data/united_states/congress/updateLegislatorVotes";
import { db, firestore } from "src/functions/firebase";
import { default as sheeter } from "./google_sheets";
import { seedLocales } from "./locales";
import { default as storager } from "./storage";

async function seed() {
    const [
        _node, // path to node binary executing file
        _file, // path to file being executed (seed.js)
        operation,
        localeName, // locale name passed into seed.sh as $2
        _env, // dotenv_config_path argument
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
        preparer().catch(console.error);
        updater().catch(console.error);
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

    seedLegislators(fireClient, locale, defaultUser);
}

seed().catch(console.error);
