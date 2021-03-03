/** @format */
import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";
import { db, firestore } from "./firebase";

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
    fireClient: SwayFireClient,
    locale: sway.ILocale | sway.IUserLocale,
) => {
    const [city, region, country] = locale.name.split("-");
    const _data = require(`${__dirname}/data/${country}/${region}/${city}/organizations`)
        .default;
    const data = get(_data, `${country}.${region}.${city}`);

    console.log("Seeding Organizations for Locale -", locale.name);
    return data.map(async (organization: sway.IOrganization) => {
        console.log("Seeding Organization -", organization.name);
        const current = await fireClient.organizations().get(organization.name);
        if (current) {
            const positionKeys = Object.keys(organization.positions);
            if (Object.keys(current.positions).length === positionKeys.length) {
                console.log(
                    "Organization position count has not changed. Skipping update for -",
                    current.name,
                );
                return;
            }
            console.log(
                "Organization positions count HAS changed. Updating -",
                current.name,
            );
            fireClient.organizations().update(organization);
        } else {
            console.log(
                "Organization does not exist. Creating -",
                organization.name,
            );
            fireClient.organizations().create(organization);
        }

        return organization;
    });
};

export const seedOrganizationsFromGoogleSheet = async (locale: sway.ILocale, organization: sway.IOrganization) => {
    const fireClient = new SwayFireClient(db, locale, firestore);

    console.log("Seeding Organization -", organization.name);
    const current = await fireClient.organizations().get(organization.name);
    if (current) {
        const positionKeys = Object.keys(organization.positions);
        if (Object.keys(current.positions).length === positionKeys.length) {
            console.log(
                "Organization position count has not changed. Skipping update for -",
                current.name,
            );
            return;
        }
        console.log(
            "Organization positions count HAS changed. Updating -",
            current.name,
        );
        fireClient.organizations().update(organization);
    } else {
        console.log(
            "Organization does not exist. Creating -",
            organization.name,
        );
        fireClient.organizations().create(organization);
    }

    return organization;
}