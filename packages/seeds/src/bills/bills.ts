/** @format */

import { Collections } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";
import { db, firestore } from "../firebase";

const addFirestoreIdToBill = (
    bill: Partial<sway.IBill>,
): Partial<sway.IBill> => {
    bill.firestoreId = bill.externalVersion
        ? bill.externalId + "v" + bill.externalVersion
        : bill.externalId;
    return bill;
};

const removeBillFunctions = {
    toFirestore: (bill: sway.IBill) => {
        return Object.keys(bill).reduce((sum: any, key: string) => {
            if (typeof bill[key] === "function") {
                return sum;
            }
            sum[key] = bill[key];
            return sum;
        }, {});
    },
    fromFirestore: function (snapshot: any) {
        return snapshot.data();
    },
};

const generateBills = (locale: sway.ILocale): Partial<sway.IBill>[] => {
    const [city, region, country] = locale.name.split("-");

    const seedData = require(`${__dirname}/../data/${country}/${region}/${city}/bills`)
        .default;

    const data = get(seedData, `${country}.${region}.${city}`);
    if (!data) return [];

    return data.map(addFirestoreIdToBill);
};

export const seedBills = (fireClient: SwayFireClient, locale: sway.ILocale): sway.IBill[] => {
    console.log("Seeding bills for locale -", locale.name);

    const bills = generateBills(locale) as sway.IBill[];

    const districtScores = locale.districts.reduce((sum, district) => {
        sum[district] = {
            for: 0,
            against: 0,
        };
        return sum;
    }, {});

    bills.forEach(async(bill: sway.IBill) => {
        console.log("Seeding bill - ", bill.firestoreId);
        const existing = await fireClient.bills().get(bill.firestoreId);
        if (!existing) {
            await fireClient.bills().create(bill.firestoreId, bill);
        }

        const existingScore = await fireClient.billScores().get(bill.firestoreId);
        if (!existingScore) {
            await fireClient.billScores().create(bill.firestoreId, {
                districts: districtScores,
            })
        }
    });

    return bills;
};
