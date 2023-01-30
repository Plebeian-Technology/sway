import SwayFireClient from "@sway/fire";
import { get } from "lodash";
import { sway } from "sway";
import { db, firestoreConstructor } from "../firebase";
import { findFilepath } from "../utils";

export default class SeedOrganizations {
    fireClient: SwayFireClient;
    locale: sway.ILocale;
    constructor(locale: sway.ILocale) {
        this.fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);
        this.locale = locale;
    }

    public seed = async () => {
        console.log(
            "SeedOrganizations.createOrganizationPositions - seeding organizations for locale -",
            this.locale.name,
        );

        const organizations = await this.getOrganizationsFromFile();

        return organizations.map(async (organization: sway.IOrganization) => {
            const existing = await this.getExistingOrganization(organization);
            if (existing) {
                const seedPositionFirestoreIds = Object.keys(organization.positions);
                const currentOrgFirestoreIds = Object.keys(existing.positions);
                if (currentOrgFirestoreIds.length === seedPositionFirestoreIds.length) {
                    console.log(
                        "SeedOrganizations.createOrganizationPositions - organization position count has not changed. Skipping update for -",
                        existing.name,
                    );
                } else {
                    await this.updateOrganizationPositions(organization);
                }
            } else {
                await this.createOrganizationPositions(organization);
            }

            return organization;
        });
    };

    private getOrganizationsFromFile = async () => {
        const [city, region, country] = this.locale.name.split("-");

        const filepath = await findFilepath(this.locale, "organizations/index.js");
        if (!filepath) {
            console.error("Could not find organizations/index.js file via glob.");
            return [];
        } else {
            console.log("Getting organizations data from filepath -", filepath);
        }

        const _data = await import(filepath).catch(console.error);

        const data = get(_data, `default.default.${country}.${region}.${city}`) as
            | sway.IOrganization[]
            | { organizations: sway.IOrganization[] };

        if (!data) {
            return [];
        } else if (Array.isArray(data)) {
            return data;
        } else {
            return data.organizations;
        }
    };

    private getExistingOrganization = async (
        organization: sway.IOrganization,
    ): Promise<sway.IOrganization | void> => {
        return this.fireClient.organizations().get(organization.name).catch(console.error);
    };

    private updateOrganizationPositions = async (organization: sway.IOrganization) => {
        console.log(
            "SeedOrganizations.createOrganizationPositions - organization positions count HAS changed. Updating -",
            organization.name,
        );
        return this.fireClient.organizations().update(organization).catch(console.error);
    };

    private createOrganizationPositions = async (organization: sway.IOrganization) => {
        console.log(
            "SeedOrganizations.createOrganizationPositions - organization does not exist. Creating -",
            organization.name,
        );
        return this.fireClient.organizations().create(organization).catch(console.error);
    };
}
