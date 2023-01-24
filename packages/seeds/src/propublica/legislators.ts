import { CONGRESS_LOCALE, ESwayLevel, STATE_CODES_NAMES, STATE_NAMES_CODES } from "@sway/constants";
import { titleize } from "@sway/utils";
import { sway } from "sway";
import { writeDataToFile } from "../utils";
import { US_GOVERNMENT_LEGISLATORS_SOCIALS_URL, US_GOVERNMENT_LEGISLATORS_URL } from "./constants";
import { propublica } from "./types";

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
            const data = usLegislators.map((l) => {
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
            });

            await writeDataToFile(CONGRESS_LOCALE, "legislators", data);
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
}
