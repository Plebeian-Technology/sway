import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";

export const seedLocales = async (
    swayFire: SwayFireClient,
    localeName: string,
): Promise<sway.ILocale | undefined> => {
    console.log("Seeding Locale -", localeName);
    const [city, region, country] = localeName.split("-");

    const postalCodesPath = `${__dirname}/../data/${country}/${region}/${city}/postalCodes`;
    const _postalCodes = require(postalCodesPath).default;
    const postalCodes = get(_postalCodes, `${country}.${region}.${city}`);

    const districtsPath = `${__dirname}/../data/${country}/${region}/${city}/districts`
    const _districts = require(districtsPath).default;
    const districts = get(_districts, `${country}.${region}.${city}`);

    const locale = await swayFire
        .locales()
        .create(city, region, country, postalCodes, districts).catch(console.error);
    if (!locale) {
        console.error("Could not create locale. Skipping rest of seeds.");
        return;
    }

    return locale;
};
