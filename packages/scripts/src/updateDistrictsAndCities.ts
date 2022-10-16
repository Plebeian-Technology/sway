// TODO: update user districts to strings ex. 1 -> MD1 and downcase all user.cities and user.countries

import { CONGRESS_LOCALE, CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject } from "@sway/utils";
import { flatten } from "lodash";
import { fire, sway } from "sway";
import { db, firestoreConstructor } from "../firebase";

const updateDistricts = async () => {
    // legislators, users and locales have districts/cities, billScores
    // users also have locales

    const withCode = (regionCode: string, district: string | number) => {
        if (!regionCode) {
            console.log("RECEIVED UNDEFINED REGION CODE, RETURNING DISTRICT", {
                regionCode,
                district,
            });
            if (district) return String(district);
            return "";
        }
        if (typeof district === "string" && district.includes(regionCode)) return district;

        return `${regionCode.toUpperCase()}${district}`;
    };

    const updateUsers = async (fireClient: SwayFireClient, locale: sway.ILocale) => {
        const snap = await fireClient.users("taco").where("city", "==", locale.city).get();

        snap.docs.forEach(async (doc: fire.TypedDocumentSnapshot<sway.IUser>) => {
            const data = doc.data();
            if (!data) return;

            const userLocales = data.locales;
            if (!userLocales) return;

            const { regionCode } = data;

            await doc.ref
                .update({
                    ...data,
                    city: data.city.toLowerCase(),
                    region: data.region.toLowerCase(),
                    regionCode: regionCode.toUpperCase(),
                    country: data.country.toLowerCase(),
                    locales: userLocales.map((uLocale: sway.IUserLocale) => {
                        uLocale.district = withCode(regionCode, uLocale.district);
                        uLocale.districts = uLocale.districts.map((d) => {
                            return withCode(regionCode, d);
                        });
                        return uLocale;
                    }),
                })
                .catch(console.error);
        });
    };

    const updateLegislators = async (fireClient: SwayFireClient, _locale: sway.ILocale) => {
        const snaps = await fireClient.legislators().collection().get();
        snaps.docs.forEach(async (snap) => {
            const data = snap.data() as sway.ILegislator;
            // console.log("LEGISLATOR DATA");
            // console.dir(data, { depth: null })

            if (!data) return;

            await snap.ref
                .update({
                    ...data,
                    district: withCode(data.regionCode, data.district),
                })
                .catch(console.error);
        });
    };

    const updateLocale = async (fireClient: SwayFireClient, locale: sway.ILocale) => {
        const snap = await fireClient.locales().snapshot(locale);
        if (!snap) return;

        const data = snap.data();
        if (!data) return;

        console.log("LOCALE DATA");
        console.dir(data, { depth: null });

        await snap.ref.update({
            ...data,
            ...locale,
            districts: locale.districts,
            // @ts-ignore
            userCount: Object.keys(data.userCount).reduce(
                (sum: { [district: string]: number }, key: number | string) => {
                    if (key === "all") {
                        sum[key] = Number(data.userCount[key]);
                        return sum;
                    }

                    if (typeof key === "string" && key.includes(locale.regionCode)) {
                        sum[key] = Number(data.userCount[key]);
                        return sum;
                    }

                    sum[withCode(locale.regionCode, key)] = Number(data.userCount[key]);
                    return sum;
                },
                {},
            ),
        });
    };

    const getBillIds = async (
        fireClient: SwayFireClient,
        locale: sway.ILocale,
    ): Promise<string[]> => {
        console.log("getting active billIds for locale - ", locale.name);
        const docs1: Promise<fire.TypedQuerySnapshot<sway.IBill>> = fireClient
            .bills()
            .collection()
            .get();

        const ids: string[] | void = await Promise.all([docs1])
            .then(([d1]) => {
                return flatten([d1.docs.map((d) => d.id)]);
            })
            .catch(console.error);

        if (!ids || isEmptyObject(ids)) return [];

        return ids;
    };

    const updateBillScores = async (
        fireClient: SwayFireClient,
        locale: sway.ILocale,
        billId: string,
    ) => {
        const snap = await fireClient.billScores().snapshot(billId);
        if (!snap) return;

        const data = snap?.data();
        if (!data) return;

        const newDistricts = Object.keys(data.districts).reduce(
            (sum: any, key: string | number) => {
                if (typeof key === "string" && key.includes(locale.regionCode)) {
                    sum[key] = data.districts[key];
                    return sum;
                }
                sum[withCode(locale.regionCode, key)] = data.districts[key];
                return sum;
            },
            {},
        );

        // console.log("UPDATE BILL SCORE -", billId, newDistricts);

        const newBillScore = {
            ...data,
            districts: newDistricts,
        };
        // console.dir(newBillScore, { depth: null });

        await snap.ref.update(newBillScore).catch(console.error);
    };

    console.log({ LOCALES });

    LOCALES.forEach(async (locale: sway.ILocale) => {
        if (locale.name === CONGRESS_LOCALE_NAME) return;

        console.log("UPDATING LOCALE -", locale.name);
        console.dir(locale, { depth: null });

        const fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);

        await updateUsers(fireClient, locale).catch(console.error);
        await updateLegislators(fireClient, locale).catch(console.error);
        await updateLocale(fireClient, locale).catch(console.error);

        const billIds = await getBillIds(fireClient, locale).catch(console.error);
        billIds &&
            billIds.forEach(async (billId: string) => {
                await updateBillScores(fireClient, locale, billId).catch(console.error);
            });
    });

    {
        const fireClient = new SwayFireClient(db, CONGRESS_LOCALE, console);
        await updateLegislators(fireClient, CONGRESS_LOCALE).catch(console.error);

        await updateUsers(fireClient, CONGRESS_LOCALE).catch(console.error);

        const billIds = await getBillIds(fireClient, CONGRESS_LOCALE).catch(console.error);
        // TODO: UPDATE USER CONGRESSIONAL LOCALES
        billIds &&
            billIds.forEach(async (billId) => {
                await updateBillScores(
                    fireClient,
                    {
                        ...CONGRESS_LOCALE,
                        regionCode: "MD", // NOTE: assuming all scores on Baltimore since only 1 DC user, 3/5/21
                    },
                    billId,
                ).catch(console.error);
            });
    }
};

updateDistricts().catch(console.error);

export default updateDistricts;
