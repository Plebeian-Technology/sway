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
    const _data =
        require(`${__dirname}/../src/data/${country}/${region}/${city}/organizations`).default;
    const data = get(_data, `${country}.${region}.${city}`);

    console.log("Seeding Organizations for Locale -", locale.name);
    return data.map(async (organization: sway.IOrganization) => {
        console.log("Seeding Organization -", organization.name);
        const current = await fireClient.organizations().get(organization.name);
        if (current) {
            const seedPositionFirestoreIds = Object.keys(organization.positions);
            const currentOrgFirestoreIds = Object.keys(current.positions);
            if (currentOrgFirestoreIds.length === seedPositionFirestoreIds.length) {
                console.log(
                    "Organization position count has not changed. Skipping update for -",
                    current.name,
                );
                return;
            }
            console.log("Organization positions count HAS changed. Updating -", current.name);
            fireClient.organizations().update(organization);
        } else {
            console.log("Organization does not exist. Creating -", organization.name);
            fireClient.organizations().create(organization);
        }

        return organization;
    });
};

export const seedOrganizationsFromGoogleSheet = async (
    locale: sway.ILocale,
    organization: sway.IOrganization,
) => {
    const fireClient = new SwayFireClient(db, locale, firestore);

    console.log("Seeding Organization -", organization.name);
    const current = await fireClient.organizations().get(organization.name);
    if (current) {
        const seedPositionFirestoreIds = Object.keys(organization.positions);
        const currentOrgFirestoreIds = Object.keys(current.positions);
        if (
            currentOrgFirestoreIds.length === seedPositionFirestoreIds.length &&
            seedPositionFirestoreIds.join(",") === currentOrgFirestoreIds.join(",")
        ) {
            console.log(
                "Organization position count has not changed. Skipping update for -",
                organization.name,
                // current,
                // organization,
            );
            return;
        }
        console.log(
            "Organization positions count HAS changed. Updating -",
            { current },
            { organization },
        );
        await fireClient.organizations().update({
            name: organization.name,
            iconPath: organization.iconPath,
            positions: {
                ...current.positions,
                ...organization.positions,
            },
        });
    } else {
        console.log("Organization does not exist. Creating -", organization.name);
        await fireClient.organizations().create(organization);
    }

    return organization;
};
