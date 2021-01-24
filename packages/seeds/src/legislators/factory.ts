import { sway } from "sway";
import { capitalize, first, last } from "lodash";
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

export interface ISeedLegislator {
    externalId: string;
    district: number;
    phone: string;
    fax: string;
    title: string;
    active: boolean;
    twitter?: string;
    email?: string;
    party: string;
    link?: string;
    photoURL?: string;
}

const withCommonFields = (
    legislator: sway.IBasicLegislator,
): sway.IBasicLegislator => {
    const externalIdNoYear = legislator.externalId
        .split("-")
        .slice(0, 2)
        .join("-");
    const firstLetterLastName = externalIdNoYear.split("-")[1][0];
    const bioguideId =
        legislator.district.toString().length === 2
            ? `${firstLetterLastName}0000${legislator.district}`
            : `${firstLetterLastName}00000${legislator.district}`;

    return {
        ...legislator,
        bioguideId: legislator.bioguideId || bioguideId,
        first_name: legislator.first_name || capitalize(first(externalIdNoYear.split("-"))),
        last_name: legislator.last_name || capitalize(last(externalIdNoYear.split("-"))),
        createdAt: firestore.FieldValue.serverTimestamp(),
        updatedAt: firestore.FieldValue.serverTimestamp(),
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
    email,
    party,
    link,
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