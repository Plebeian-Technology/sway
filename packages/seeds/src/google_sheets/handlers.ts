import SwayFireClient from "@sway/fire";
import { sway } from "sway";
import { seedBillsFromGoogleSheet } from "../bills";
import { db, firestore } from "../firebase";
import {
    createNonExistingLegislatorVote,
    seedLegislatorsFromGoogleSheet,
} from "../legislators";
import { seedLocales } from "../locales";
import { seedOrganizationsFromGoogleSheet } from "../organizations";

const getFirestoreId = (billId: string, billVersion: string) => {
    return billVersion
        ? `${billId}v${billVersion}`.toLowerCase()
        : billId.toLowerCase();
};

const updateLegislators = (
    rows: {
        title: string;
        firstName: string;
        lastName: string;
        externalId: string;
        inOffice: "0" | "1";
        party: string;
        district: string;
        phone: string;
        email: string;
        twitter: string;
        photoURL: string;
        link: string;
        street: string;
        street2: string;
        zip: string;
    }[],
    locale: sway.ILocale,
    options: {
        rootDirectory: string;
    },
) => {
    const legislators: sway.IBasicLegislator[] = rows.map((row) => {
        const { firstName, lastName, ..._row } = row;

        return {
            ..._row,
            city: locale.city.toLowerCase(),
            region: locale.region.toLowerCase(),
            regionCode: locale.regionCode.toUpperCase(),
            country: locale.country.toLowerCase(),
            first_name: firstName,
            last_name: lastName,
            inOffice: Boolean(row.inOffice && row.inOffice === "1"),
            district: row.district.includes(locale.regionCode.toUpperCase())
                ? row.district
                : `${locale.regionCode.toUpperCase()}${Number(row.district)}`,
        };
    });
    seedLegislatorsFromGoogleSheet(locale, legislators);
};

const updateBills = (
    rows: {
        title: string;
        externalId: string;
        externalVersion: string;
        chamber: string;
        status: sway.TBillStatus;
        votedate: string;
        sponsorExternalId: string;
        category: string;
        link: string;
        isCurrentSession: "0" | "1";
        summary: string;
        summaryAudio: string;
        summaryAudioProvider: string;
        isTweeted: "0" | "1";
        isInitialNotificationsSent: "0" | "1";
    }[],
    locale: sway.ILocale,
) => {
    const bills: sway.IBill[] = rows.map((row) => {
        const {
            isCurrentSession,
            summary,
            summaryAudio,
            summaryAudioProvider,
            ..._row
        } = row;
        return {
            ..._row,
            active: Boolean(isCurrentSession && isCurrentSession === "1"),
            summaries: {
                sway: summary,
                swayAudioBucketPath: summaryAudio,
                swayAudioByline: summaryAudioProvider,
            },
            firestoreId: getFirestoreId(row.externalId, row.externalVersion),
            isTweeted: Boolean(row.isTweeted && row.isTweeted === "1"),
            isInitialNotificationsSent: Boolean(row.isInitialNotificationsSent && row.isInitialNotificationsSent === "1")
        } as sway.IBill;
    });
    seedBillsFromGoogleSheet(locale, bills);
};

const updateLegislatorVotes = (
    rows: {
        externalBillId: string;
        externalBillVersion: string;
        externalLegislatorId: string;
        legislatorSupport: "for" | "against" | "abstain";
    }[],
    locale: sway.ILocale,
) => {
    const fireClient = new SwayFireClient(db, locale, firestore);
    return rows.map(async (row) => {
        await createNonExistingLegislatorVote(
            fireClient,
            getFirestoreId(row.externalBillId, row.externalBillVersion),
            row.externalLegislatorId,
            row.legislatorSupport.toLowerCase() as
                | "for"
                | "against"
                | "abstain",
        );
    });
};

const updateOrganizations = (
    rows: {
        name: string;
        icon: string;
        externalBillId: string;
        externalBillVersion: string;
        support: "For" | "Against";
        summary: string;
    }[],
    locale: sway.ILocale,
) => {
    const getSupport = (support: "For" | "Against") => {
        if (support === "For") return true;
        if (support === "Against") return false;
        throw new Error(
            `Support was neither For nor Against, received - ${support}`,
        );
    };
    return rows.map((row) => {
        const organization = {
            name: row.name,
            iconPath: row.icon,
            positions: {
                [getFirestoreId(row.externalBillId, row.externalBillVersion)]: {
                    billFirestoreId: getFirestoreId(
                        row.externalBillId,
                        row.externalBillVersion,
                    ),
                    support: getSupport(row.support),
                    summary: row.summary,
                },
            },
        };
        seedOrganizationsFromGoogleSheet(locale, organization);
        return organization;
    });
};

const updateLocale = (
    rows: {
        city: string;
        region: string;
        regionCode: string;
        country: string;
        districts: string;
        icon: string;
        spreadsheetId: string;
    }[],
    locale: sway.ILocale,
) => {
    seedLocales(locale.name);
};

export const handlers = {
    Locale: updateLocale,
    Legislators: updateLegislators,
    LegislatorVotes: updateLegislatorVotes,
    Bills: updateBills,
    Organizations: updateOrganizations,
};

// * NOTE: Do this manually, locale is associated with spreadsheetId
// const updateLocalesFile = async (
//     rows: {
//         city: string;
//         region: string;
//         regionCode: string;
//         country: string;
//         districts: string;
//         icon: string;
//     }[],
//     options: {
//         rootDirectory: string;
//     },
// ): Promise<sway.ILocale | undefined> => {
//     const LOCALES_FILEPATH = fspath.resolve(
//         `${options.rootDirectory}/constants/locales.json`,
//     );
//     if (isEmptyObject(rows)) return;

//     const { city, region, regionCode, country, districts, icon } = rows[0];
//     const localeName = toLocaleName(city, region, country);
//     const locale = findLocale(localeName);
//     if (locale) {
//         console.error(`Locale - ${localeName} - is already seeded. Skipping.`);
//         return locale;
//     }
//     const newLocale = await fspromises
//         .readFile(LOCALES_FILEPATH, "utf8")
//         .then((content: string) => {
//             const json: sway.ILocale[] = JSON.parse(content);
//             const _newLocale = {
//                 city,
//                 region,
//                 regionCode,
//                 country,
//                 districts: districts.split(",").map(Number),
//                 icon,
//                 name: localeName,
//             };
//             const updated = [...json, _newLocale];
//             return fspromises
//                 .writeFile(LOCALES_FILEPATH, JSON.stringify(updated, null, 4), {
//                     encoding: "utf8",
//                 })
//                 .then(() => _newLocale)
//                 .catch(console.error);
//         })
//         .catch(console.error);

//     return newLocale as sway.ILocale;
// };
