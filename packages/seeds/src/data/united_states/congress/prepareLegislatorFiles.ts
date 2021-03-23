import * as fs from "fs";
import fetch from "node-fetch";
import { STATE_CODES_NAMES, STATE_NAMES_CODES } from "@sway/constants";
import { ESwayLevel } from "@sway/constants";
import { sway } from "sway";
import { titleize } from "@sway/utils";

// * PROPUBLICA_API_KEY: https://www.propublica.org/datastore/api/propublica-congress-api
// * GOOGLE_MAPS_API_KEY: https://developers.google.com/maps/documentation/embed/get-api-key
// * OPEN_STATES_API_KEY: https://openstates.org/api/register/
// * GEOCODIO_API_KEY: https://dash.geocod.io/login
// * IP_STACK_API_KEY: https://ipstack.com/signup/free

const CONGRESS = 117;

const PROPUBLICA_HEADERS = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "X-API-Key": process.env.PROPUBLICA_API_KEY || "",
};

interface IPropublicaLegislator {
    id: string;
    title: string;
    short_title: string;
    api_uri: string;
    first_name: string;
    middle_name: string | null;
    last_name: string;
    suffix: string | null;
    district?: string;
    date_of_birth: string;
    gender: string;
    party: string;
    leadership_role: string | null;
    twitter_account: string;
    facebook_account: string;
    youtube_account: string;
    govtrack_id: string;
    cspan_id: string;
    votesmart_id: string;
    icpsr_id: string;
    crp_id: string;
    google_entity_id: string;
    fec_candidate_id: string;
    url: string;
    rss_url: string;
    contact_form: string;
    in_office: boolean;
    cook_pvi: number | null;
    dw_nominate: number;
    ideal_point: number | null;
    seniority: string;
    next_election: string;
    total_votes: number;
    missed_votes: number;
    total_present: number;
    last_updated: string;
    ocd_id: string;
    office: string;
    phone: string;
    fax: string;
    state: string;
    senate_class: string;
    state_rank: string;
    lis_id: string;
    missed_votes_pct: number;
    votes_with_party_pct: number;
    votes_against_party_pct: number;
}

const getDistrict = (legislator: IPropublicaLegislator) => {
    const { state, district } = legislator;
    const stateCode =
        state.length === 2
            ? state.toUpperCase()
            : STATE_NAMES_CODES[titleize(state)].toUpperCase();
    if (
        district &&
        district !== "null" &&
        district.toLowerCase() !== "at-large"
    ) {
        return `${stateCode}${Number(district)}`;
    }

    return `${stateCode}0`;
};

const reducer = (sum: sway.IBasicLegislator[], l: IPropublicaLegislator) => {
    let stateCode = "";
    let state = l.state;
    if (state.length === 2) {
        stateCode = state;
        state = STATE_CODES_NAMES[state.toUpperCase()];
    } else {
        stateCode = STATE_NAMES_CODES[state];
    }

    const item = {
        street: l.office,
        city: STATE_CODES_NAMES[l.state].toLowerCase().replace(" ", "_"),
        region: state.toLowerCase(),
        regionCode: stateCode.toUpperCase(),
        zip: "",
        first_name: l.first_name,
        last_name: l.last_name,
        externalId: l.id,
        district: getDistrict(l),
        phone: l.phone,
        fax: l.fax,
        title: l.short_title,
        active: l.in_office,
        twitter: l.twitter_account,
        party: l.party,
        photoURL: `${process.env.CONGRESS_IMAGE_REPO_URL}/${l.id}.jpg`,
        link: l.url,
        email: l.contact_form,
        level: ESwayLevel.Congress,
    };
    sum.push(item);
    return sum;
};

const house = `${process.env.PROPUBLICA_ORIGIN}/${CONGRESS}/house/members.json`;
const senate = `${process.env.PROPUBLICA_ORIGIN}/${CONGRESS}/senate/members.json`;

const get = (url: string) => {
    console.log("FETCHING -", url);

    return fetch(url, { headers: PROPUBLICA_HEADERS })
        .then((res) => res.json())
        .then((json) => json.results[0].members.reduce(reducer, []))
        .catch(console.error);
};

export default () =>
    Promise.all([get(house), get(senate)])
        .then(([housers, senators]) => {
            const path = `${__dirname}/congress/legislators`;
            console.log("PATH -", path);
            const data = {
                united_states: {
                    congress: {
                        congress: housers.concat(senators),
                    },
                },
            };

            console.log("DATA FOR LEGISLATORS");
            console.log("WRITING DATA TO PATH -", path);
            fs.mkdir(path, { recursive: true }, (err) => {
                if (err) throw err;

                console.log(
                    "CREATED DIRECTORY, WRITING FILE -",
                    `${path}/index.ts`,
                );
                fs.stat(`${path}/../../index.ts`, (statError, stat) => {
                    if (statError) {
                        fs.writeFile(
                            `${path}/../../index.ts`,
                            'export * from "./congress"',
                            (fileWriteError) => {
                                if (fileWriteError) throw fileWriteError;
                            },
                        );
                    } else {
                        fs.truncate(`${path}/../../index.ts`, 0, () => {
                            fs.writeFile(
                                `${path}/../../index.ts`,
                                'export * from "./congress"',
                                (fileWriteError) => {
                                    if (fileWriteError) throw fileWriteError;
                                },
                            );
                        });
                    }
                });

                fs.stat(`${path}/../index.ts`, (statError, stat) => {
                    if (statError) {
                        fs.writeFile(
                            `${path}/../index.ts`,
                            'export * from "./legislators"',
                            (fileWriteError) => {
                                if (fileWriteError) throw fileWriteError;
                            },
                        );
                    } else {
                        fs.truncate(`${path}/../index.ts`, 0, () => {
                            fs.writeFile(
                                `${path}/../index.ts`,
                                'export * from "./legislators"',
                                (fileWriteError) => {
                                    if (fileWriteError) throw fileWriteError;
                                },
                            );
                        });
                    }
                });

                console.log("WRITE LEGISLATOR DATA FILE");
                fs.stat(`${path}/index.ts`, (statError, stat) => {
                    if (statError) {
                        fs.writeFile(
                            `${path}/index.ts`,
                            `export default ${JSON.stringify(data)}`,
                            (fileWriteError) => {
                                if (fileWriteError) throw fileWriteError;
                            },
                        );
                    } else {
                        fs.truncate(`${path}/index.ts`, 0, (truncateError) => {
                            if (truncateError) throw truncateError;
                            fs.writeFile(
                                `${path}/index.ts`,
                                `export default ${JSON.stringify(
                                    data,
                                    null,
                                    4,
                                )}`,
                                (fileWriteError) => {
                                    if (fileWriteError) throw fileWriteError;
                                },
                            );
                        });
                    }
                });
            });
        })
        .catch(console.error);
