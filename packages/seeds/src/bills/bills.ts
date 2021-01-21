/** @format */

import { Collections } from "@sway/constants";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { get } from "lodash";

const addFirestoreIdToBill = (
    bill: Partial<sway.IBill>,
): Partial<sway.IBill> => {
    bill.createdAt = firestore.FieldValue.serverTimestamp();
    bill.updatedAt = firestore.FieldValue.serverTimestamp();
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

export const seedBills = (locale: sway.ILocale): sway.IBill[] => {
    console.log("Seeding bills for locale -", locale.name);

    const bills = generateBills(locale) as sway.IBill[];

    const districtScores = locale.districts.reduce((sum, district) => {
        sum[district] = {
            for: 0,
            against: 0,
        };
        return sum;
    }, {});

    bills.forEach((bill: sway.IBill) => {
        console.log("Seeding bill - ", bill.firestoreId);
        db.collection(Collections.Bills)
            .doc(locale.name)
            .collection(Collections.Bills)
            .doc(bill.firestoreId)
            .withConverter(removeBillFunctions)
            .set(bill)
            .then(() => console.log("success bill seed"))
            .catch(console.error);

        db.collection(Collections.BillScores)
            .doc(locale.name)
            .collection(Collections.BillScores)
            .doc(bill.firestoreId)
            .set({
                createdAt: firestore.FieldValue.serverTimestamp(),
                updatedAt: firestore.FieldValue.serverTimestamp(),
                for: 0,
                against: 0,
                districts: districtScores,
            });
    });

    return bills;
};
