import { ESwayLevel, STATE_CODES_NAMES, STATE_NAMES_CODES } from "@sway/constants";
import { titleize } from "@sway/utils";
import * as fs from "fs/promises";
import * as path from "path";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

import { sway } from "sway";

// * PROPUBLICA_API_KEY: https://www.propublica.org/datastore/api/propublica-congress-api
// * GOOGLE_MAPS_API_KEY: https://developers.google.com/maps/documentation/embed/get-api-key
// * OPEN_STATES_API_KEY: https://openstates.org/api/register/
// * GEOCODIO_API_KEY: https://dash.geocod.io/login
// * IP_STACK_API_KEY: https://ipstack.com/signup/free

// const PROPUBLICA_HEADERS = {
//     Accept: "application/json",
//     "Content-Type": "application/json",
//     "X-API-Key": process.env.PROPUBLICA_API_KEY || "",
// };

interface IUSLegislator {
    id: {
        bioguide: string;
        thomas: string;
        lis: string;
        govtrack: number;
        opensecrets: string;
        votesmart: number;
        fec: string[];
        cspan: number;
        wikipedia: string;
        house_history: number;
        ballotpedia: string;
        maplight: number;
        icpsr: number;
        wikidata: string;
        google_entity_id: string;
    };
    name: {
        first: string;
        last: string;
        official_full: string;
    };
    bio: {
        birthday: string;
        gender: "M" | "F";
    };
    terms: {
        type: string;
        start: string;
        end: string;
        state: string;
        party: "Democrat" | "Republican";
        class: number;
        url: string;
        address: string;
        phone: string;
        fax: string;
        contact_form: string;
        office: string;
        state_rank: string;
        rss_url: string;
        district?: number;
    }[];
}

interface IUSLegislatorSocial {
    id: {
        bioguide: string;
        thomas: string;
        govtrack: number;
    };
    social: {
        twitter: string;
        facebook: string;
        youtube: string;
        youtube_id: string;
        twitter_id: string;
        instagram: string;
    };
}

// interface IPropublicaLegislator {
//     id: string;
//     title: string;
//     short_title: string;
//     api_uri: string;
//     first_name: string;
//     middle_name: string | null;
//     last_name: string;
//     suffix: string | null;
//     district?: string;
//     date_of_birth: string;
//     gender: string;
//     party: string;
//     leadership_role: string | null;
//     twitter_account: string;
//     facebook_account: string;
//     youtube_account: string;
//     govtrack_id: string;
//     cspan_id: string;
//     votesmart_id: string;
//     icpsr_id: string;
//     crp_id: string;
//     google_entity_id: string;
//     fec_candidate_id: string;
//     url: string;
//     rss_url: string;
//     contact_form: string;
//     in_office: boolean;
//     cook_pvi: number | null;
//     dw_nominate: number;
//     ideal_point: number | null;
//     seniority: string;
//     next_election: string;
//     total_votes: number;
//     missed_votes: number;
//     total_present: number;
//     last_updated: string;
//     ocd_id: string;
//     office: string;
//     phone: string;
//     fax: string;
//     state: string;
//     senate_class: string;
//     state_rank: string;
//     lis_id: string;
//     missed_votes_pct: number;
//     votes_with_party_pct: number;
//     votes_against_party_pct: number;
// }

const reducer = (sum: sway.IBasicLegislator[], l: IUSLegislator) => {
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
        street: l.terms.last().address.toUpperCase().split("WASHINGTON DC").first().trim() || "",
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

const usgovernment = "https://theunitedstates.io/congress-legislators/legislators-current.json";
const usgovernment_socials =
    "https://theunitedstates.io/congress-legislators/legislators-social-media.json";
// const propublica_house = `https://api.propublica.org/congress/v1/${CONGRESS}/house/members.json`;
// const propublica_senate = `https://api.propublica.org/congress/v1/${CONGRESS}/senate/members.json`;

/**
 * Mapping legislator from the unitedstate.io current-legislators list
 * to a Sway-readable legislator in packages/seeds/src/legislators/factory.ts
 *
 * https://theunitedstates.io/congress-legislators/legislators-current.json
 */
const getUsGovernment = (url: string) => {
    return fetch(url)
        .then((res) => res.json())
        .then((json) => (json as IUSLegislator[]).reduce(reducer, []))
        .catch((e) => {
            console.error(e);
            return [];
        });
};

const getUsGovernmentSocials = (url: string): Promise<IUSLegislatorSocial[]> => {
    return fetch(url)
        .then((res) => res.json())
        .then((json) => json as IUSLegislatorSocial[])
        .catch((e) => {
            console.error(e);
            return [];
        });
};

// const getPropublica = (url: string): Promise<IPropublicaLegislator[]> => {
//     console.log("FETCHING -", url);

//     return fetch(url, { headers: PROPUBLICA_HEADERS })
//         .then((res) => res.json())
//         .then((json) => (json as any).results[0].members as IPropublicaLegislator[])
//         .catch((e) => {
//             console.error(e);
//             return [];
//         });
// };

export default async () => {
    const socials = await getUsGovernmentSocials(usgovernment_socials).catch((e) => {
        console.error(e);
        return [];
    });

    return getUsGovernment(usgovernment)
        .then(async (usLegislators) => {
            const root = path.resolve(__dirname).replace("/dist", "");
            const dir = `${root}/congress/legislators`;
            console.log("ROOT + DIR -", {
                root,
                dir,
            });
            const data = {
                united_states: {
                    congress: {
                        congress: usLegislators.map((l) => {
                            const social = socials.find(
                                (s) => s.id.bioguide.toLowerCase() === l.externalId.toLowerCase(),
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
            };

            // console.log("DATA FOR LEGISLATORS");
            // console.dir(data, { depth: null });
            console.log("WRITING DATA TO PATH -", `${dir}/index.ts`);
            await fs.mkdir(dir, { recursive: true }).then(async () => {
                console.log("CREATED DIRECTORY, WRITING FILE -", `${dir}/index.ts`);
                await fs
                    .stat(`${dir}/../../index.ts`)
                    .catch(async () => {
                        await fs
                            .writeFile(`${dir}/../../index.ts`, 'export * from "./congress"')
                            .then(() => {
                                console.log(`WROTE FILE TO PATH - ${dir}/../../index.ts`);
                            })
                            .catch(console.error);
                    })
                    .then(async () => {
                        await fs
                            .truncate(`${dir}/../../index.ts`, 0)
                            .then(async () => {
                                await fs
                                    .writeFile(
                                        `${dir}/../../index.ts`,
                                        'export * from "./congress"',
                                    )
                                    .then(() => {
                                        console.log(`WROTE FILE TO PATH - ${dir}/../../index.ts`);
                                    })
                                    .catch(console.error);
                            })
                            .catch(console.error);
                    });
            });

            await fs
                .stat(`${dir}/../index.ts`)
                .catch(async () => {
                    await fs
                        .writeFile(
                            `${dir}/../index.ts`,
                            'export * from "./legislators"\nexport * from "./bills"\nexport * from "./organizations"\nexport * from "./legislator_votes"',
                        )
                        .then(() => {
                            console.log(`WROTE FILE TO PATH - ${dir}/../index.ts`);
                        })
                        .catch(console.error);
                })
                .then(async () => {
                    await fs
                        .truncate(`${dir}/../index.ts`, 0)
                        .then(async () => {
                            await fs
                                .writeFile(
                                    `${dir}/../index.ts`,
                                    'export * from "./legislators"\nexport * from "./bills"\nexport * from "./organizations"\nexport * from "./legislator_votes"',
                                )
                                .then(() => {
                                    console.log(`WROTE FILE TO PATH - ${dir}/../index.ts`);
                                })
                                .catch(console.error);
                        })
                        .catch(console.error);
                });

            console.log(`WRITE LEGISLATOR DATA FILE - ${dir}/index.ts`);
            await fs
                .writeFile(`${dir}/index.ts`, `export default ${JSON.stringify(data, null, 4)}`)
                .then(() => {
                    console.log(`WROTE FILE TO PATH - ${dir}/index.ts`);
                })
                .catch(console.error);
        })
        .catch(console.error);
};
