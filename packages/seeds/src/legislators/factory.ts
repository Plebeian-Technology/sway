import { Timestamp } from "firebase-admin/firestore";
import { capitalize, first, last } from "lodash";
import { sway } from "sway";
import { firestore } from "../firebase";

const BALTIMORE_OFFICE_LOCATION = {
    street: "100 Holliday Street",
    street2: "Suite 500",
    city: "Baltimore",
    region: "Maryland",
    regionCode: "MD",
    zip: "21202",
};

const DC_OFFICE_LOCATION = {
    street: "1350 Pennsylvania Avenue, NW",
    street2: "",
    city: "Washington",
    region: "District of Columbia",
    regionCode: "DC",
    zip: "20004",
};

const LA_OFFICE_LOCATION = {
    street: "200 North Spring Street",
    street2: "",
    city: "Los Angeles",
    region: "California",
    regionCode: "CA",
    zip: "90012",
};

export interface ISeedLegislator {
    externalId: string;
    district: string;
    phone: string;
    fax: string;
    title: string;
    active: boolean;
    twitter?: string;
    email?: string;
    party: string;
    link?: string;
    photoURL?: string;
    street2?: string;
}

const withCommonFields = (legislator: Partial<sway.IBasicLegislator>): sway.IBasicLegislator => {
    if (!legislator.externalId || !legislator.district) {
        throw new Error(
            `Missing external id or district for legislator in withCommonFields - ${JSON.stringify(
                legislator,
            )}`,
        );
    }
    const externalIdNoYear = legislator.externalId.split("-").slice(0, 2).join("-");
    const now = new Date();
    return {
        ...legislator,
        first_name: legislator.first_name || capitalize(first(externalIdNoYear.split("-"))),
        last_name: legislator.last_name || capitalize(last(externalIdNoYear.split("-"))),
        createdAt: now,
        updatedAt: now,
    } as sway.IBasicLegislator;
};

export const generateBaltimoreLegislator = ({
    externalId,
    district,
    phone,
    fax,
    title,
    active,
    twitter,
    party,
    photoURL,
}: ISeedLegislator): sway.IBasicLegislator => {
    const externalIdNoYear = externalId.split("-").slice(0, 2).join("-");
    return withCommonFields({
        ...BALTIMORE_OFFICE_LOCATION,
        externalId,
        active,
        title,
        link: `https://baltimorecity.gov/${externalIdNoYear}`,
        email: `${externalIdNoYear.replace("-", ".")}@baltimorecity.gov`,
        district,
        phone,
        fax,
        party,
        photoURL,
        twitter,
    } as sway.IBasicLegislator);
};

export const generateDCLegislator = ({
    externalId,
    district,
    phone,
    fax,
    title,
    active,
    twitter,
    email,
    party,
    photoURL,
    link,
}: ISeedLegislator): sway.IBasicLegislator => {
    return withCommonFields({
        ...DC_OFFICE_LOCATION,
        externalId,
        active,
        title,
        link,
        email,
        district,
        phone,
        fax,
        party,
        photoURL: photoURL || "",
        twitter,
    } as sway.IBasicLegislator);
};

export const generateLosAngelesLegislator = ({
    externalId,
    district,
    phone,
    fax,
    title,
    active,
    twitter,
    email,
    party,
    photoURL,
    link,
    street2,
}: ISeedLegislator): sway.IBasicLegislator => {
    return withCommonFields({
        ...LA_OFFICE_LOCATION,
        street2: street2 || "",
        externalId,
        active,
        title,
        link,
        email,
        district,
        phone,
        fax,
        party,
        photoURL: photoURL || "",
        twitter,
    } as sway.IBasicLegislator);
};
