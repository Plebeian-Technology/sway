import { Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { sway } from "sway";

export const seedUserVotes = (swayFire: SwayFireClient, uid: string, bills: sway.IBill[]) => {
    console.log("seeding user votes");

    bills.forEach((bill: sway.IBill) => {
        swayFire
            .userVotes(uid)
            .create(bill.firestoreId, Math.random() > 0.5 ? Support.For : Support.Against)
            .catch(console.error);
    });
};
