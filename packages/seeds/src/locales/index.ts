import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";

const seedPostalCodes = (city: string, region: string, country: string) => {
    const postalCodesPath = `${__dirname}/../data/${country}/${region}/${city}/postalCodes`;
    const _postalCodes = require(postalCodesPath).default;
    return get(_postalCodes, `${country}.${region}.${city}`);
}

const seedDistricts = (city: string, region: string, country: string) => {
    const districtsPath = `${__dirname}/../data/${country}/${region}/${city}/districts`
    const _districts = require(districtsPath).default;
    return get(_districts, `${country}.${region}.${city}`);
}

export const seedLocales = async (
    swayFire: SwayFireClient,
    localeName: string,
): Promise<sway.ILocale | undefined> => {
    console.log("Seeding Locale -", localeName);
    const [city, region, country] = localeName.split("-");

    const postalCodes = region === "congress" ? [] : seedPostalCodes(city, region, country)
    const districts = region === "congress" ? [] : seedDistricts(city, region, country)

    const locale = await swayFire
        .locales()
        .create(city, region, country, postalCodes, districts).catch(console.error);
    if (!locale) {
        console.error("Could not create locale. Skipping rest of seeds.");
        return;
    }

    return locale;
};
