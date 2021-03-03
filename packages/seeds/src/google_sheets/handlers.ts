import SwayFireClient from "@sway/fire";
import { sway } from "sway";
import { seedBillsFromGoogleSheet } from "../bills";
import { db, firestore } from "../firebase";
import {
    createNonExistingLegislatorVote,
    seedLegislatorsFromGoogleSheet,
} from "../legislators";
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
        return {
            ...row,
            city: locale.city,
            region: locale.region,
            regionCode: locale.regionCode,
            country: locale.country,
            first_name: row.firstName,
            last_name: row.lastName,
            inOffice: Boolean(row.inOffice && row.inOffice === "1"),
            district: Number(row.district),
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
        sponsorExternalId: string;
        category: string;
        link: string;
        isActive: "0" | "1";
        summary: string;
        summaryAudio: string;
        summaryAudioProvider: string;
        votedate: string;
    }[],
    locale: sway.ILocale,
) => {
    const bills: sway.IBill[] = rows.map((row) => {
        const {
            isActive,
            summary,
            summaryAudio,
            summaryAudioProvider,
            ..._row
        } = row;
        return {
            ..._row,
            isActive: isActive === "1",
            summaries: {
                sway: summary,
                swayAudioBucketPath: summaryAudio,
                swayAudioByline: summaryAudioProvider,
            },
            firestoreId: getFirestoreId(row.externalId, row.externalVersion),
            isTweeted: false,
            isInitialNotificationsSent: false,
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
            row.legislatorSupport,
        );
    });
};

const updateOrganizations = (
    rows: {
        name: string;
        icon: string;
        externalBillId: string;
        externalBillVersion: string;
        support: "0" | "1";
        summary: string;
    }[],
    locale: sway.ILocale,
) => {
    const organization = {
        name: rows[0].name,
        iconPath: rows[0].icon,
        positions: rows.reduce((sum: any, row: any) => {
            sum = {
                ...sum,
                [getFirestoreId(row.externalBillId, row.externalBillVersion)]: {
                    billFirestoreId: getFirestoreId(
                        row.externalBillId,
                        row.externalBillVersion,
                    ),
                    support: row.support === "1",
                    summary: row.summary,
                },
            };
            return sum;
        }, {}),
    };
    seedOrganizationsFromGoogleSheet(locale, organization);
};

export const handlers = {
    Locale: () => null,
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
