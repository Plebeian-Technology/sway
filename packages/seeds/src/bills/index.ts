/** @format */

import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";
import { db, firestoreConstructor } from "../firebase";

export default class SeedBills {
    fireClient: SwayFireClient;
    locale: sway.ILocale;
    constructor(locale: sway.ILocale) {
        this.fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);
        this.locale = locale;
    }

    public seed = async () => {
        const bills = await this.getBillsFromFile();

        bills.forEach(async (bill: sway.IBill) => {
            const existing = await this.fireClient.bills().get(bill.firestoreId);
            if (!existing) {
                await this.createBillFirestore(bill);
            } else {
                await this.updateBillFirestore(bill);
            }

            const existingScore = await this.fireClient.billScores().get(bill.firestoreId);
            if (!existingScore) {
                await this.createBillScoreFirestore(bill);
            }
        });

        return bills;
    };

    private getBillsFromFile = async (): Promise<sway.IBill[]> => {
        const [city, region, country] = this.locale.name.split("-");

        const seedData = await import(
            `${__dirname}/../data/${country}/${region}/${city}/bills/index.js`
        ).catch((e) => {
            console.error(e);
            return {};
        });

        const data = get(seedData, `default.default.${country}.${region}.${city}`) as
            | sway.IBill[]
            | { bills: sway.IBill[] };

        if (!data) {
            return [];
        } else {
            return (Array.isArray(data) ? data : data.bills).map(this.addFirestoreIdToBill);
        }
    };

    private getDistrictScoresForLocale = () => {
        return this.locale.districts.reduce((sum, district: string) => {
            if (district === `${this.locale.regionCode.toUpperCase()}0`) return sum;

            sum[district] = {
                for: 0,
                against: 0,
            };
            return sum;
        }, {});
    };

    private createBillFirestore = async (bill: sway.IBill) => {
        return this.fireClient.bills().create(bill.firestoreId, {
            ...bill,
            swayReleaseDate: (() => {
                const date = new Date();
                date.setFullYear(date.getFullYear() + 1);
                return date;
            })(),
        });
    };

    private updateBillFirestore = async (bill: sway.IBill) => {
        return this.fireClient
            .bills()
            .update({} as sway.IUserVote, {
                firestoreId: bill.firestoreId,
                swayReleaseDate:
                    bill.swayReleaseDate ||
                    (() => {
                        const date = new Date();
                        date.setHours(date.getHours() - 24 * 7);
                        return date;
                    })(),
                active: bill.active,
            })
            .catch(console.error);
    };

    private createBillScoreFirestore = async (bill: sway.IBill) => {
        await this.fireClient.billScores().create(bill.firestoreId, {
            districts: this.getDistrictScoresForLocale(),
        });
    };

    private addFirestoreIdToBill = (bill: sway.IBill): sway.IBill => {
        bill.firestoreId = bill.externalVersion
            ? bill.externalId + "v" + bill.externalVersion
            : bill.externalId;
        return bill;
    };
}
