/** @format */

import { sway } from "sway";
import { random } from "lodash";
import { firestore } from "../firebase";
import SwayFireClient from "@sway/fire";

export const seedBillScores = async (
    swayFire: SwayFireClient,
    billFirestoreId: string,
): Promise<void> => {
    console.log("seeding bill score for bill -", billFirestoreId);

    const users = await swayFire.users("").list();
    const usersEachDistrict =
        users &&
        users.reduce((sum: sway.IPlainObject, user: sway.IUser) => {
            user.locales.forEach((locale: sway.IUserLocale) => {
                if (swayFire?.locale?.name !== locale.name) return;

                const district = locale.district;
                if (!district || sum[district]) return sum;

                sum[district] = {
                    for: 0,
                    against: 0,
                };
            });
            return sum;
        }, {});

    swayFire
        .billScores()
        .create(billFirestoreId, {
            districts: usersEachDistrict || {},
        })
        .catch((error: Error) => {
            console.error("promise catch failed to create bill score");
            console.error(error);
        });
};
