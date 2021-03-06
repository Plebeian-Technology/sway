import { BALTIMORE_CITY_LOCALE_NAME, LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";
import { db, firestore } from "../firebase";

const testFireClient = async () => {

    const locale: sway.IUserLocale = {
        ...LOCALES.find((l) => l.name === BALTIMORE_CITY_LOCALE_NAME),
        district: "MD1",
    } as sway.IUserLocale;
    if (!locale) return;

    const fireClient = new SwayFireClient(db, locale, firestore);

    const billIds = await getBillIds(fireClient);
    console.log({ billIds });
};

const getUsersCountInLocale = async (
    fireClient: SwayFireClient,
): Promise<
    | {
          countAllUsersInLocale: number;
          countAllUsersInDistrict: number;
      }
    | undefined
> => {
    const locale = fireClient.locale as sway.IUserLocale;
    if (!locale) return;

    const data = await fireClient.locales().get(locale);
    if (!data) return;

    return {
        countAllUsersInLocale: Number(data.userCount.all),
        countAllUsersInDistrict: Number(data.userCount[locale.district]),
    };
};

const getLegislatorVote = async (
    fireClient: SwayFireClient,
    legislator: sway.ILegislator,
    billFirestoreId: string,
): Promise<sway.ILegislatorVote | undefined> => {
    return fireClient
        .legislatorVotes()
        .get(legislator.externalId, billFirestoreId);
};

const getBillIds = async (fireClient: SwayFireClient): Promise<string[]> => {
    const snap = await fireClient.bills().where("active", "==", true).get();
    const ids = snap.docs.map((b) => b.id);
    return ids;
};

const getBillScores = async (
    fireClient: SwayFireClient,
    legislator: sway.ILegislator,
    billFirestoreId: string,
) => {
    const scores = await fireClient.billScores().get(billFirestoreId);
    if (!scores) return;

    return {
        all: {
            for: scores.for,
            against: scores.against,
        },
        district: {
            for: get(scores, `${legislator.district}.for`),
            against: get(scores, `${legislator.district}.against`),
        },
    };
};

testFireClient();

export default testFireClient;
