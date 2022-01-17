/** @format */

import SwayFireClient from "src/fire";
import { get } from "lodash";
import { sway } from "sway";
import { db, firestore } from "src/seeds/firebase";

const addFirestoreIdToBill = (
    bill: Partial<sway.IBill>,
): Partial<sway.IBill> => {
    bill.firestoreId = bill.externalVersion
        ? bill.externalId + "v" + bill.externalVersion
        : bill.externalId;
    return bill;
};

const generateBills = (locale: sway.ILocale): Partial<sway.IBill>[] => {
    const [city, region, country] = locale.name.split("-");

    const seedData =
        require(`${__dirname}/../data/${country}/${region}/${city}/bills`).default;

    const data = get(seedData, `${country}.${region}.${city}`);
    if (!data) return [];

    return data.map(addFirestoreIdToBill);
};

export const seedBills = (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
): sway.IBill[] => {
    console.log("Seeding bills for locale -", locale.name);

    const bills = generateBills(locale) as sway.IBill[];

    return _seed(fireClient, locale, bills);
};

export const seedBillsFromGoogleSheet = (
    locale: sway.ILocale,
    bills: sway.IBill[],
) => {
    const fireClient = new SwayFireClient(db, locale, firestore);

    return _seed(fireClient, locale, bills);
};

const _seed = (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
    bills: sway.IBill[],
) => {
    const districtScores = locale.districts.reduce((sum, district: string) => {
        if (district === `${locale.regionCode.toUpperCase()}0`) return sum;

        sum[district] = {
            for: 0,
            against: 0,
        };
        return sum;
    }, {});

    bills.forEach(async (bill: sway.IBill) => {
        const existing = await fireClient.bills().get(bill.firestoreId);
        if (!existing) {
            console.log("Seeding bill - ", bill.firestoreId);
            await fireClient.bills().create(bill.firestoreId, bill);
        } else {
            console.log(
                "Bill",
                bill.firestoreId,
                "already exists. Updating only sway summary.",
            );
            // await fireClient.bills().update({} as sway.IUserVote, {
            //     "summaries.sway": bill.summaries.sway
            // })
        }

        const existingScore = await fireClient
            .billScores()
            .get(bill.firestoreId);
        if (!existingScore) {
            console.log("Seeding bill scores - ", bill.firestoreId);
            await fireClient.billScores().create(bill.firestoreId, {
                districts: districtScores,
            });
        } else {
            console.log(
                "Scores for bill",
                bill.firestoreId,
                "already exist. Skipping seed.",
            );
        }
    });

    return bills;
};
