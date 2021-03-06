// TODO: update user districts to strings ex. 1 -> MD1 and downcase all user.cities and user.countries

import { CONGRESS_LOCALE, LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject, LOCALES_WITHOUT_CONGRESS } from "@sway/utils";
import { flatten, isNumber } from "lodash";
import { fire, sway } from "sway";
import { db, firestore } from "../firebase";

const updateDistricts = async () => {
    // legislators, users and locales have districts/cities, billScores
    // users also have locales

    const withCode = (regionCode: string, district: string | number) => {
        if (typeof district === "string" && district.includes(regionCode))
            return district;

        return `${regionCode.toUpperCase()}${district}`;
    };

    const updateUsers = async (
        fireClient: SwayFireClient,
        locale: sway.ILocale,
    ) => {
        const snap = await fireClient
            .users("taco")
            .where("city", "==", locale.city)
            .get();

        snap.docs.forEach(
            async (doc: fire.TypedDocumentSnapshot<sway.IUser>) => {
                const data = doc.data();
                if (!data) return;

                const userLocales = data.locales;
                if (!userLocales) return;

                await doc.ref
                    .update({
                        ...data,
                        city: data.city.toLowerCase(),
                        region: data.region.toLowerCase(),
                        regionCode: data.regionCode.toUpperCase(),
                        country: data.country.toLowerCase(),
                        locales: userLocales.map(
                            (uLocale: sway.IUserLocale) => {
                                const { regionCode } = uLocale;
                                uLocale.district = withCode(
                                    regionCode,
                                    uLocale.district,
                                );
                                uLocale.districts = uLocale.districts.map(
                                    (d) => {
                                        return withCode(regionCode, d);
                                    },
                                );
                                return uLocale;
                            },
                        ),
                    })
                    .catch(console.error);
            },
        );
    };

    const updateLegislators = async (
        fireClient: SwayFireClient,
        locale: sway.ILocale,
    ) => {
        const snaps = await fireClient.legislators().collection().get();
        snaps.docs.forEach(async (snap) => {
            const data = snap.data() as sway.ILegislator;
            await snap.ref
                .update({
                    ...data,
                    district: withCode(data.regionCode, data.district),
                })
                .catch(console.error);
        });
    };

    const updateLocale = async (
        fireClient: SwayFireClient,
        locale: sway.ILocale,
    ) => {
        const snap = await fireClient.locales().snapshot(locale);
        if (!snap) return;

        const data = snap.data();
        if (!data) return;

        await snap.ref.update({
            ...data,
            districts: data.districts.map((d: string | number) =>
                withCode(data.regionCode, d),
            ),
            // @ts-ignore
            userCount: Object.keys(data.userCount).reduce(
                (sum: { [district: string]: number }, key: number | string) => {
                    if (key === "all") {
                        sum[key] = Number(data.userCount[key]);
                        return sum;
                    }

                    if (
                        typeof key === "string" &&
                        key.includes(locale.regionCode)
                    ) {
                        sum[key] = Number(data.userCount[key]);
                        return sum;
                    }

                    sum[withCode(data.regionCode, key)] = Number(
                        data.userCount[key],
                    );
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
        const docs1: Promise<
            fire.TypedQuerySnapshot<sway.IBill>
        > = fireClient.bills().collection().get();

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
                if (
                    typeof key === "string" &&
                    key.includes(locale.regionCode)
                ) {
                    sum[key] = data.districts[key];
                    return sum;
                }
                sum[withCode(locale.regionCode, key)] = data.districts[key];
                return sum;
            },
            {},
        );

        console.log("UPDATE BILL SCORE -", billId, newDistricts);

        const newBillScore = {
            ...data,
            districts: newDistricts,
        };
        console.dir(newBillScore, { depth: null });

        await snap.ref.update(newBillScore).catch(console.error);
    };

    LOCALES_WITHOUT_CONGRESS.forEach(async (locale: sway.ILocale) => {
        const fireClient = new SwayFireClient(db, locale, firestore);

        await updateUsers(fireClient, locale);
        await updateLegislators(fireClient, locale);
        await updateLocale(fireClient, locale);

        const billIds = await getBillIds(fireClient, locale);
        billIds.forEach(async (billId) => {
            await updateBillScores(fireClient, locale, billId);
        });
    });

    {
        const fireClient = new SwayFireClient(db, CONGRESS_LOCALE, firestore);
        await updateLegislators(fireClient, CONGRESS_LOCALE);

        const billIds = await getBillIds(fireClient, CONGRESS_LOCALE);
        billIds.forEach(async (billId) => {
            await updateBillScores(fireClient, {
                ...CONGRESS_LOCALE,
                regionCode: "MD" // NOTE: assuming all scores on Baltimore since only 1 DC user, 3/5/21
            }, billId);
        });
    }
};

updateDistricts();

export default updateDistricts;
