/** @format */
import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";

interface ISeedPosition {
    billFirestoreId: string;
    support: boolean;
    summary: string;
}

interface ISeedOrg {
    name: string;
    iconPath: string;
    positions: {
        [key: string]: ISeedPosition;
    };
}

export const seedOrganizations = (
    swayFire: SwayFireClient,
    locale: sway.ILocale | sway.IUserLocale,
) => {
    const [city, region, country] = locale.name.split("-");
    const _data = require(`${__dirname}/data/${country}/${region}/${city}/organizations`).default;
    const data = get(_data, `${country}.${region}.${city}`);

    console.log("Seeding Organizations");
    return data.map(async(organization: sway.IOrganization) => {
        console.log("Seeding Organization -", organization.name);

        swayFire.organizations().create(organization);
        return organization;
    });
};
