/** @format */

import SwayFireClient from "@sway/fire";
import { sway } from "sway";
import * as seeds from "./src";
import { db, firestore } from "./src/firebase";
import { SEED_UID } from "./src/utils";
import {default as preparer} from "./src/data/united_states/congress/prepareLegislatorFiles"

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
        return;
    }

    console.log("Creating swayFire client.");
    const swayFire = new SwayFireClient( // @ts-ignore
        db,
        { name: localeName } as sway.ILocale,
        firestore,
    );

    const locale = await seeds.seedLocales(swayFire, localeName);
    if (!locale) {
        console.error("could not seed locale -", localeName);
        return;
    }

    const defaultUser = { locale: { name: locale.name } } as sway.IUser;
    const user: sway.IUser = seeds.seedUsers(SEED_UID, locale) || defaultUser;

    seeds.seedLegislators(swayFire, locale, user);
}

seed();
