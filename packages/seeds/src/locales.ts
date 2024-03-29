import { LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { fromLocaleNameItem, titleize, toLocaleName } from "@sway/utils";
import { flatten, isEmpty } from "lodash";
import { sway } from "sway";
import { db, firestoreConstructor } from "./firebase";

export const seedLocales = async (localeName?: string) => {
    LOCALES.filter((l) => {
        if (!localeName) return true;
        return l.name === localeName;
    }).forEach(async (locale: sway.ILocale) => {
        const client = new SwayFireClient(db, locale, firestoreConstructor, console);
        const exists = await client.locales().exists(locale);
        if (!exists) {
            console.log("Seeding locale to firestore -", locale.name);

            const newLocaleUsers: sway.ILocaleUsers = {
                ...locale,
                userCount: locale.districts.reduce(
                    (sum: any, district: string) => {
                        sum[district] = 0;
                        return sum;
                    },
                    { all: 0 },
                ),
            };
            await client.locales().create(newLocaleUsers).catch(console.error);
        }

        const current = await client.locales().get(locale);
        if (!current) {
            console.error("Could not get ILocaleUsers for locale -", locale.name);
            return;
        }

        const users = await getUsers(client);
        if (!users || isEmpty(users)) {
            console.error("Skipping locale seed, users is empty for locale -", locale.name);
            return;
        }

        console.log("Updating locale users for locale -", locale.name);

        users.forEach(async (user: sway.IUser) => {
            const uLocale = user.locales.find((l) => l.name === locale.name);
            if (!uLocale) return;

            await client
                .locales()
                .addUserToCount(current, uLocale.district, { addToAll: true })
                .catch(console.error);
        });
    });

    const _getUsersLowerCaseLocale = async (
        client: SwayFireClient,
        locale: sway.ILocale,
    ): Promise<sway.IUser[]> => {
        return client
            .users("taco-as-uid-because-uid-is-required")
            .where("city", "==", fromLocaleNameItem(locale.city).toLowerCase())
            .where("regionCode", "==", locale.regionCode.toUpperCase())
            .where("country", "==", titleize(fromLocaleNameItem(locale.country)))
            .get()
            .then((docs) => {
                return docs.docs.map((d) => d.data());
            })
            .catch((error) => {
                console.error(error);
                return [];
            });
    };
    const _getUsersUpperCaseLocale = async (
        client: SwayFireClient,
        locale: sway.ILocale,
    ): Promise<sway.IUser[]> => {
        return client
            .users("taco-as-uid-because-uid-is-required")
            .where("city", "==", fromLocaleNameItem(locale.city).toUpperCase())
            .where("regionCode", "==", locale.regionCode.toUpperCase())
            .where("country", "==", titleize(fromLocaleNameItem(locale.country)))
            .get()
            .then((docs) => {
                return docs.docs.map((d) => d.data());
            })
            .catch((error) => {
                console.error(error);
                return [];
            });
    };
    const _getUsersTitleizedLocale = async (
        client: SwayFireClient,
        locale: sway.ILocale,
    ): Promise<sway.IUser[]> => {
        return client
            .users("taco-as-uid-because-uid-is-required")
            .where("city", "==", titleize(fromLocaleNameItem(locale.city)))
            .where("regionCode", "==", locale.regionCode.toUpperCase())
            .where("country", "==", titleize(fromLocaleNameItem(locale.country)))
            .get()
            .then((docs) => {
                return docs.docs.map((d) => d.data());
            })
            .catch((error) => {
                console.error(error);
                return [];
            });
    };

    const getUsers = async (client: SwayFireClient) => {
        const locale = client.locale;
        if (!locale) return;

        const users: sway.IUser[] | void = await Promise.all([
            _getUsersLowerCaseLocale(client, locale),
            _getUsersUpperCaseLocale(client, locale),
            _getUsersTitleizedLocale(client, locale),
        ])
            .then((datas: sway.IUser[][] | void) => {
                if (!datas) return [];
                return flatten(datas);
            })
            .catch(console.error);

        if (!users || isEmpty(users)) return;

        users.forEach(async (user: sway.IUser) => {
            console.log("seed.locales.getUsers - Updating User.city -", {
                userCity: user.city,
                localeCity: locale.city.toLowerCase(),
            });
            if (user.city === locale.city.toLowerCase() || !user.uid) return;

            console.log("Updating user city to match locale city.");
            await client
                .users(user.uid)
                .update({
                    ...user,
                    city: locale.city.toLowerCase(),
                })
                .catch(console.error);
        });

        return users.filter((user: sway.IUser) => {
            const lname = toLocaleName(user.city, user.region, user.country);
            const uLocale = user.locales.filter((l) => l.name === lname);
            return !!uLocale;
        });
    };
};
