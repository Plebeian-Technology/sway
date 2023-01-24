import * as fs from "fs/promises";
import { get, random } from "lodash";
import * as path from "path";
import { sway } from "sway";
import { propublica } from "./propublica/types";

export const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
export const isTest = process.env.NODE_ENV === "test";

export const SEED_UID = `demo-user-${random(1, 100000)}`;

export const writeDataToFile = async (
    locale: sway.ILocale,
    key: "legislators" | "bills" | "organizations" | "legislator_votes",
    data:
        | sway.IBasicLegislator[]
        | sway.IBill[]
        | sway.ILegislatorVote[]
        | sway.IOrganization[]
        | propublica.IDataFileLegislatorVote,
) => {
    if (!locale) {
        throw new Error("No locale passed to writeDataToFile");
    }
    if (!key) {
        throw new Error("No key passed to writeDataToFile");
    }
    if (!data) {
        throw new Error("No data passed to writeDataToFile");
    }

    const structure = {
        [locale.country]: { [locale.region]: { [locale.city]: { [key]: data } } },
    };

    const accessor = `${locale.country}.${locale.region}.${locale.city}`;
    const isLegislators = !!get(structure, `${accessor}.legislators`);
    const isBills = !!get(structure, `${accessor}.bills`);
    const isOrganizations = !!get(structure, `${accessor}.organizations`);
    const isLegislatorVotes = !!get(structure, `${accessor}.legislator_votes`);

    const suffix = (() => {
        if (isLegislators) return "legislators";
        if (isBills) return "bills";
        if (isOrganizations) return "organizations";
        if (isLegislatorVotes) return "legislator_votes";
    })();
    if (!suffix) {
        throw new Error(
            "Could not determine suffix for filepath. Did NOT receive one of legislators | bills | organizations | legislator_votes",
        );
    }

    const root = path.resolve(__dirname).replace("/dist", "");
    const directory = `${root}/../data/${locale.country}/${locale.region}/${locale.city}/${suffix}`;

    // Root should be:
    // ./packages/seeds/src/legislators
    console.log("writeDataToFile - ROOT + DIR -", {
        root,
        directory,
        isLegislators,
        isBills,
        isOrganizations,
        isLegislatorVotes,
        country: locale.country,
        region: locale.region,
        city: locale.city,
    });

    console.log("WRITING DATA TO PATH -", `${directory}/index.ts`);
    await fs.mkdir(directory, { recursive: true }).then(async () => {
        console.log("CREATED DIRECTORY, WRITING FILE -", `${directory}/index.ts`);
        await fs
            .stat(`${directory}/../../index.ts`)
            .catch(async () => {
                await fs
                    .writeFile(`${directory}/../../index.ts`, `export * from "./${locale.city}"`)
                    .then(() => {
                        console.log(`WROTE FILE TO PATH - ${directory}/../../index.ts`);
                    })
                    .catch(console.error);
            })
            .then(async () => {
                await fs
                    .truncate(`${directory}/../../index.ts`, 0)
                    .then(async () => {
                        await fs
                            .writeFile(
                                `${directory}/../../index.ts`,
                                `export * from "./${locale.city}"`,
                            )
                            .then(() => {
                                console.log(`WROTE FILE TO PATH - ${directory}/../../index.ts`);
                            })
                            .catch(console.error);
                    })
                    .catch(console.error);
            });
    });

    await fs
        .stat(`${directory}/../index.ts`)
        .catch(async () => {
            await fs
                .writeFile(`${directory}/../index.ts`, "")
                .then(() => {
                    console.log(`WROTE FILE TO PATH - ${directory}/../index.ts`);
                })
                .catch(console.error);
        })
        .then(async () => {
            await fs
                .readFile(`${directory}/../index.ts`, "utf-8")
                .then(async (fileContents: string) => {
                    if (isLegislators && !fileContents.includes("legislators")) {
                        await fs
                            .appendFile(
                                `${directory}/../index.ts`,
                                '\nexport * from "./legislators"\n',
                            )
                            .then(() =>
                                console.log(
                                    `export * from "./legislators" APPENDED TO ${directory}/../index.ts`,
                                ),
                            )
                            .catch(console.error);
                    }
                    if (isBills && !fileContents.includes("bills")) {
                        await fs
                            .appendFile(`${directory}/../index.ts`, '\nexport * from "./bills"\n')
                            .then(() =>
                                console.log(
                                    `export * from "./bills" APPENDED TO ${directory}/../index.ts`,
                                ),
                            )
                            .catch(console.error);
                    }
                    if (isOrganizations && !fileContents.includes("organizations")) {
                        await fs
                            .appendFile(
                                `${directory}/../index.ts`,
                                '\nexport * from "./organizations"\n',
                            )
                            .then(() =>
                                console.log(
                                    `export * from "./organizations" APPENDED TO ${directory}/../index.ts`,
                                ),
                            )
                            .catch(console.error);
                    }
                    if (isLegislatorVotes && !fileContents.includes("legislator_votes")) {
                        await fs
                            .appendFile(
                                `${directory}/../index.ts`,
                                '\nexport * from "./legislator_votes"\n',
                            )
                            .then(() =>
                                console.log(
                                    `export * from "./legislator_votes" APPENDED TO ${directory}/../index.ts`,
                                ),
                            )
                            .catch(console.error);
                    }
                })
                .catch(console.error);
        });

    console.log(`WRITE DATA FILE - ${directory}/index.ts`);
    await fs
        .writeFile(
            `${directory}/index.ts`,
            `
// Auto-generated from packages/seeds/src/legislators/prepareLegislatorFiles.ts

export default ${JSON.stringify(structure, null, 4)}`,
        )
        .then(() => {
            console.log(`WROTE FILE TO PATH - ${directory}/index.ts`);
        })
        .catch(console.error);
};
