import { CONGRESS_LOCALE, ESwayLevel, STATE_CODES_NAMES, STATE_NAMES_CODES } from "@sway/constants";
import { titleize } from "@sway/utils";
import * as fs from "fs/promises";
import { get } from "lodash";
import * as path from "path";
import { sway } from "sway";
import { US_GOVERNMENT_LEGISLATORS_SOCIALS_URL, US_GOVERNMENT_LEGISLATORS_URL } from "./constants";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

// * PROPUBLICA_API_KEY: https://www.propublica.org/datastore/api/propublica-congress-api
// * GOOGLE_MAPS_API_KEY: https://developers.google.com/maps/documentation/embed/get-api-key
// * OPEN_STATES_API_KEY: https://openstates.org/api/register/
// * GEOCODIO_API_KEY: https://dash.geocod.io/login
// * IP_STACK_API_KEY: https://ipstack.com/signup/free

export default class PropublicaLegislators {
    public getLegislatorsToFile = async () => {
        const socials = await this.getUsGovernmentSocials(
            US_GOVERNMENT_LEGISLATORS_SOCIALS_URL,
        ).catch((e) => {
            console.error(e);
            return [];
        });

        return this.getUsGovernment(US_GOVERNMENT_LEGISLATORS_URL).then(async (usLegislators) => {
            const data = {
                united_states: {
                    congress: {
                        congress: {
                            legislators: usLegislators.map((l) => {
                                const social = socials.find(
                                    (s) =>
                                        s.id.bioguide.toLowerCase() === l.externalId.toLowerCase(),
                                );
                                if (social) {
                                    return {
                                        ...l,
                                        twitter: social.social.twitter || "",
                                    };
                                } else {
                                    return l;
                                }
                            }),
                        },
                    },
                },
            };

            await this.writeDataToFile(CONGRESS_LOCALE, data);
        });
    };

    /**
     * Mapping legislator from the unitedstate.io current-legislators list
     * to a Sway-readable legislator in packages/seeds/src/legislators/factory.ts
     *
     * https://theunitedstates.io/congress-legislators/legislators-current.json
     */
    private getUsGovernment = (url: string) => {
        const reducer = (sum: sway.IBasicLegislator[], l: propublica.ILegislator) => {
            let stateCode = "";
            let state = l.terms.last().state.trim();
            if (state.length === 2) {
                stateCode = state.trim();
                state = STATE_CODES_NAMES[state.toUpperCase()].trim();
            } else {
                stateCode = STATE_NAMES_CODES[state].trim();
            }

            const item = {
                first_name: l.name.first,
                last_name: l.name.last,
                externalId: l.id.bioguide.toUpperCase().trim(),
                district: l.terms.last().district ? String(l.terms.last().district) : "",
                phone: l.terms.last().phone || "",
                fax: l.terms.last().fax || "",
                title: titleize(l.terms.last().type) + ".",
                active: true,
                twitter: "",
                email: l.terms.last().contact_form || "",
                link: l.terms.last().contact_form || "",
                photoURL: `https://raw.githubusercontent.com/unitedstates/images/gh-pages/congress/225x275/${l.id.bioguide}.jpg`,
                // photoURL: `${process.env.CONGRESS_IMAGE_REPO_URL}/${l.id.bioguide}_200.jpg`,
                level: ESwayLevel.Congress,
                street:
                    l.terms.last().address.toUpperCase().split("WASHINGTON DC").first().trim() ||
                    "",
                street2: "",
                street3: "",
                city: state.toLowerCase(),
                region: state.toLowerCase(),
                regionCode: stateCode.toUpperCase(),
                zip: l.terms.last().address.split(" ").last().split("-").first().trim(),
                party: l.terms.last().party,
            } as sway.IBasicLegislator;
            sum.push(item);
            return sum;
        };

        return fetch(url)
            .then((res) => res.json())
            .then((json) => (json as propublica.ILegislator[]).reduce(reducer, []))
            .catch((e) => {
                console.error(e);
                return [];
            });
    };

    private getUsGovernmentSocials = (url: string): Promise<propublica.ILegislatorSocial[]> => {
        return fetch(url)
            .then((res) => res.json())
            .then((json) => json as propublica.ILegislatorSocial[])
            .catch((e) => {
                console.error(e);
                return [];
            });
    };

    private writeDataToFile = async (
        locale: sway.ILocale,
        data: Record<
            string, // united_states
            Record<
                string, // maryland
                Record<
                    string, // baltimore
                    Record<
                        string, // legislators | bills | organizations | legislator_votes
                        | sway.IBasicLegislator[]
                        | sway.IBill[]
                        | sway.ILegislatorVote[]
                        | sway.IOrganization[]
                        | propublica.IDataFileLegislatorVote
                    >
                >
            >
        >,
    ) => {
        const accessor = `${locale.country}.${locale.region}.${locale.city}`;
        const isLegislators = !!get(data, `${accessor}.legislators`);
        const isBills = !!get(data, `${accessor}.bills`);
        const isOrganizations = !!get(data, `${accessor}.organizations`);
        const isLegislatorVotes = !!get(data, `${accessor}.legislator_votes`);

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
        // console.dir(data, { depth: null });

        // console.log("DATA FOR LEGISLATORS");
        // console.dir(data, { depth: null });
        console.log("WRITING DATA TO PATH -", `${directory}/index.ts`);
        await fs.mkdir(directory, { recursive: true }).then(async () => {
            console.log("CREATED DIRECTORY, WRITING FILE -", `${directory}/index.ts`);
            await fs
                .stat(`${directory}/../../index.ts`)
                .catch(async () => {
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
                                .appendFile(
                                    `${directory}/../index.ts`,
                                    '\nexport * from "./bills"\n',
                                )
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
    
    export default ${JSON.stringify(data, null, 4)}`,
            )
            .then(() => {
                console.log(`WROTE FILE TO PATH - ${directory}/index.ts`);
            })
            .catch(console.error);
    };
}
