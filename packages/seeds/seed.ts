/** @format */

import { findLocale, isCongressLocale } from "@sway/utils";
import { sway } from "sway";

import { default as sheeter } from "./src/google_sheets";
import { seedLocales } from "./src/locales";
import PropublicaLegislators from "./src/propublica/legislators";
import PropublicaLegislatorVotes from "./src/propublica/legislator_votes";
import Seeder from "./src/seeder";
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

    const operations = {
        storage: () => {
            storager();
        },
        locales: async () => {
            await seedLocales().catch(console.error);
        },
        prepare: async (locale: sway.ILocale | undefined) => {
            if (isCongressLocale(locale)) {
                console.log("Run Congress Legislator Preparer");
                const ppLegislators = new PropublicaLegislators();
                await ppLegislators.getLegislatorsToFile();

                const ppLegislatorVotes = new PropublicaLegislatorVotes();
                await ppLegislatorVotes.createLegislatorVotes();
            }
        },
        sheets: (locale: sway.ILocale | undefined) => {
            if (locale) {
                sheeter(locale);
            }
        },
        seed: async (locale: sway.ILocale | undefined) => {
            if (locale) {
                const seeder = new Seeder(locale);
                await seeder.seed();
            }
        },
    };

    if (operations[operation]) {
        await operations[operation](findLocale(localeName));
    }
}

seed().catch(console.error);
