/** @format */

import { LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { sway } from "sway";
import { db, firestore } from "../firebase";

export const seedBillScores = async (billFirestoreId: string): Promise<void> => {
    console.log("seeding bill score for bill -", billFirestoreId);

    LOCALES.forEach((locale: sway.ILocale) => {
        const districts = locale.districts.reduce((sum: sway.IPlainObject, district: string) => {
            if (!district || sum[district]) return sum;

            sum[district] = {
                for: 0,
                against: 0,
            };
            return sum;
        }, {});
        const swayFire = new SwayFireClient(db, locale, console);
        swayFire
            .billScores()
            .create(billFirestoreId, {
                districts,
            })
            .catch((error: Error) => {
                console.error("promise catch failed to create bill score");
                console.error(error);
            });
    }, {});
};
