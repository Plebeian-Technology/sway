/** @format */

import { CONGRESS_LOCALE } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { findLocale } from "@sway/utils";
import { sway } from "sway";
import * as seeds from "./src";
import { default as preparer } from "./src/data/united_states/congress/prepareLegislatorFiles";
import { default as updater } from "./src/data/united_states/congress/updateLegislatorVotes";
import { db, firestoreConstructor } from "./src/firebase";
import { default as sheeter } from "./src/google_sheets";
import { seedLocales } from "./src/locales";
import { default as storager } from "./src/storage";

const OPERATIONS = ["locales", "prepare", "storage", "sheets", "seed"];

async function seed() {
    const [
        // eslint-disable-next-line
        _node, // path to node binary executing file
        // eslint-disable-next-line
        _file, // path to file being executed (seed.js)
        operation, // locales, prepare, storage, sheets
        localeName, // locale name passed into seed.sh as $2
        // eslint-disable-next-line
        _env, // dotenv_config_path argument
    ] = process.argv;

    if (!OPERATIONS.includes(operation)) {
        throw new Error(
            `Operation - ${operation} - is NOT an accepted operation. Expected one of: ${OPERATIONS.join(
                ", ",
            )}`,
        );
    }

    if (!localeName && operation !== "locales") {
        throw new Error(
            `No localeName received by seed.ts/js. Locale names passed to seed script must be in the form <city>-<region>-<country>. Received: ${localeName}. Exiting without seeding.`,
        );
    }

    const locale = findLocale(localeName);
    if (!locale && operation !== "locales") {
        throw new Error(`Locale with name - ${localeName} - not in LOCALES. Skipping seeds.`);
    }

    if (operation === "locales") {
        console.log("Run Seed Locales");
        await seedLocales().catch(console.error);
        return;
    }

    if (operation === "prepare") {
        console.log("Run Propublica Preparer");
        preparer()
            .then(() => {
                updater().catch(console.error);
            })
            .catch(console.error);
        return;
    }

    if (operation === "storage") {
        console.log("Run storage asset uploader.");
        storager();
        return;
    }

    if (operation === "sheets" && locale) {
        console.log("Run Google Sheets runner.");
        sheeter(locale);
        return;
    }

    console.log("Creating fireClient client.");
    const fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);

    const defaultUser = { locales: [locale, CONGRESS_LOCALE] } as sway.IUser;

    if (locale) {
        seeds.seedLegislators(fireClient, locale, defaultUser).catch(console.error);
    }
}

seed().catch(console.error);
