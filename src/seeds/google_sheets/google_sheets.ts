/**
 * Documentation for the Google Sheets API can be found here:
 * https://developers.google.com/sheets/api/quickstart/nodejs
 *
 * Read the below environment variables from .env.${ENVIRONMENT} for Sheets OAuth
 * Credentials are not owned by firebase account, because Sheets aren't either
 * GOOGLE_SHEETS_API_CLIENT_ID
 * GOOGLE_SHEETS_API_CLIENT_SECRET
 *
 * npm install googleapis@39 --save
 */

import * as fs from "fs";
import { Auth, google } from "googleapis";
import * as fspath from "path";
import { isEmptyObject } from "src/utils";
import { sway } from "sway";
import { authorize } from "./auth";
import { SHEET_HEADERS, SHEET_HEADER_KEYS } from "./constants";
import { handlers } from "./handlers";

const ROOT_DIRECTORY = fspath.resolve(`${__dirname}/../../../../..`);
const LOCALE_ASSET_DIRECTORIES = ["audio", "legislators", "organizations"];

type TWorkbookSheetNames =
    | "Locales"
    | "Legislators"
    | "LegislatorVotes"
    | "Bills"
    | "Organizations";

// eslint-disable-next-line
enum EWorkbookSheetNames {
    Locales = "Locales",
    Legislators = "Legislators",
    LegislatorVotes = "LegislatorVotes",
    Bills = "Bills",
    Organizations = "Organizations",
}

type TSheetValues = {
    [key in EWorkbookSheetNames]: string | number | null | undefined;
};

/**
 * Load client secrets from a local file.
 * Authorize a client with credentials, then call the Google Sheets API.
 *
 * @param {sway.ILocale} locale
 */
const runner = (locale: sway.ILocale) => {
    const path = fspath.resolve(
        `${ROOT_DIRECTORY}/keys/sheets-api-credentials.json`,
    );
    console.log("Reading credentials from -", path);
    fs.readFile(path, "utf8", (err: Error | null, content: string) => {
        if (err) return console.log("Error loading client secret file:", err);
        authorize(JSON.parse(content), locale, work);
    });
};

/**
 * Work with a spreadsheet from a locale:
 * @see https://docs.google.com/spreadsheets/d/1gTg19Lev54xqH744oPCMXrM3vFnLywNxwiTD_ZHAyHE/edit
 * @param {google.auth.OAuth2} auth The authenticated Google OAuth client.
 */
const work = async (auth: Auth.OAuth2Client, locale: sway.ILocale) => {
    if (!locale.spreadsheetId) {
        throw new Error(
            `Could not find spreadsheetId for locale - ${locale.name}. Make sure the locale is in locales.json with a spreadsheetId`,
        );
    }

    LOCALE_ASSET_DIRECTORIES.forEach((directory) => {
        fs.mkdir(
            `${ROOT_DIRECTORY}/packages/seeds/assets/${locale.name}/${directory}`,
            { recursive: true },
            console.error,
        );
    });

    const data: TSheetValues = await getSheetData(auth, locale.spreadsheetId);
    console.log("TSheetValues data:");
    console.dir(data, { depth: null });

    for (const sheet in data) {
        const rows = data[sheet];
        const handler = handlers[sheet];
        handler(rows, locale, { rootDirectory: ROOT_DIRECTORY });
    }
};

const getSheetData = async (auth: Auth.OAuth2Client, spreadsheetId: string) => {
    const sheets = google.sheets({ version: "v4", auth });
    const promises = (
        Object.keys(SHEET_HEADER_KEYS) as TWorkbookSheetNames[]
    ).map((sheet: TWorkbookSheetNames) => {
        return sheets.spreadsheets.values
            .get({
                spreadsheetId,
                range: `${sheet}!A2:21000`,
            })
            .then((res: any) => {
                if (!res) {
                    console.log("No data from API", res);
                    return;
                }
                const rows: string[][] = res.data.values;
                if (!rows || isEmptyObject(rows)) {
                    console.error("No rows in sheet -", sheet);
                    return;
                }
                return {
                    [sheet]: rows
                        .map((row: string[]): TSheetValues[] | undefined => {
                            if (row.includes("etc.")) return;
                            if (isEmptyObject(row)) return;

                            return SHEET_HEADER_KEYS[sheet].reduce(
                                (
                                    sum: TSheetValues,
                                    key: string,
                                    index: number,
                                ): TSheetValues => {
                                    const value = row[index];
                                    if (!value) {
                                        const header =
                                            SHEET_HEADERS[sheet][index];
                                        if (header.endsWith("*")) {
                                            throw new Error(
                                                `Key/Header - ${key}/${header} - is required but value was empty - ${value}`,
                                            );
                                        }
                                        sum[key] = "";
                                        return sum;
                                    }
                                    sum[key] = value.replace("ex. ", "");
                                    return sum;
                                },
                                {},
                            );
                        })
                        .filter(Boolean),
                };
            })
            .catch(console.error);
    });

    const awaited = (await Promise.all(promises)).filter(Boolean);
    return awaited.reduce((sum: any, item: any) => {
        const key = Object.keys(item)[0];
        sum[key] = item[key];
        return sum;
    }, {});
};

export default runner;
