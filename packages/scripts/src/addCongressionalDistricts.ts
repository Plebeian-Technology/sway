import { QueryDocumentSnapshot } from "@google-cloud/firestore";
import { Collections, CONGRESS_LOCALE, LOCALES } from "@sway/constants";
import { fromLocaleNameItem, isEmptyObject } from "@sway/utils";
import { sway } from "sway";
import { db as firestore, firestoreConstructor } from "../firebase";

// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

// import census from "citysdk";
// @ts-ignore
const census = (...args) => import("citysdk").then(({ default: census }) => census(...args)); // eslint-disable-line

interface ICensusData {
    vintage: string; // ex. "2018"
    geoHierarchy: {
        state: string; // ex. "24"
        "congressional district": string; // ex. "03"
    };
}
interface IGeocodeResponse {
    lat: number;
    lon: number;
}

const BASE_OSM_URL = "https://nominatim.openstreetmap.org/search";
const BASE_GOOGLE_URL = "https://maps.googleapis.com/maps/api/geocode/json";

const createLocale = (
    currentLocale: sway.IUserLocale | sway.ILocale,
    district: number,
): sway.IUserLocale | void => {
    const locale = LOCALES.find((l: sway.ILocale) => l.name === currentLocale.name);
    if (!locale) return;

    return {
        ...locale,
        district: `${locale.regionCode.toUpperCase()}${district}`,
    };
};

const geocodeOSM = async (doc: sway.IUser): Promise<IGeocodeResponse | undefined | void> => {
    const address1 = doc.address1.toLowerCase();
    const city = doc.city.toLowerCase();
    const region = doc.region.toLowerCase();
    const country = doc.country.toLowerCase().replace("_", " ");
    const postalCode = doc.postalCode.toLowerCase();

    const url = `${BASE_OSM_URL}?street=${address1}&city=${city}&state=${region}&country=${country}&postalcode=${postalCode}&format=json&limit=1`;

    console.log("URL 1 for OSM Congress Geocode", url);
    return fetch(url)
        .then((response) => {
            if (response && response.ok) return response.json();
            console.warn("OSM geocode response NOT okay");
            console.warn(response.status);
            console.warn(response.statusText);
            throw new Error("Bad response from OSM Geocoding API");
        })
        .then((json: sway.IPlainObject) => {
            if (!json) {
                console.error("No json received from OSM geocode API for url: ", url);
                return;
            }

            const location = json[0];
            if (!location) {
                console.error("no location from OSM json ->", json);
                return;
            }
            return {
                lat: location.lat,
                lon: location.lon,
            };
        })
        .catch((error: Error) => {
            console.error("Error geocoding address with OSM");
            console.error(error);
            throw error;
        });
};

const geocodeGoogle = async (doc: sway.IUser): Promise<IGeocodeResponse | void> => {
    console.log("Geocoding Congress with Google");
    const apikey = process.env.GOOGLE_MAPS_API_KEY;
    if (!apikey) {
        console.error("Could not resolve google api key from - functions.config().geocode.apikey");
        return;
    }
    const address1 = doc.address1.toLowerCase();
    const address2 = doc.address2 && doc.address2.toLowerCase();
    const city = doc.city.toLowerCase();
    const region = doc.region.toLowerCase();
    const postalCode = doc.postalCode.toLowerCase();
    const street = `${address1}${address2 ? " " + address2 : ""}`;
    const address = `${street}, ${city}, ${region} ${postalCode}`;

    const url = `${BASE_GOOGLE_URL}?address=${address}&key=${apikey}`;
    return fetch(url)
        .then((response) => {
            if (response && response.ok) return response.json();
            console.warn("Google geocode response NOT okay");
            console.warn(response.status);
            console.warn(response.statusText);
            throw new Error("Bad response from Google Geocoding API");
        })
        .then((json: sway.IPlainObject) => {
            if (!json) {
                return console.error(
                    "No json received from Google geocode API for address: ",
                    address,
                );
            }

            const location: { lat: number; lng: number } =
                json && json.results && json.results[0] && json.results[0]?.geometry?.location;
            if (!location) {
                console.log(json);
                return console.error("No geometry location in google json");
            }

            return {
                lat: location.lat,
                lon: location.lng,
            };
        })
        .catch((error: Error) => {
            console.error("Error google geocoding address");
            console.error(error);
            throw error;
        });
};

const getUserCongressionalDistrict = ({
    currentLocale,
    lat,
    lng,
    snap,
}: {
    currentLocale: sway.IUserLocale;
    lat: number;
    lng: number;
    snap: QueryDocumentSnapshot;
}) => {
    const district = currentLocale.district;
    census(
        {
            vintage: 2020,
            geoHierarchy: {
                "congressional district": {
                    lat,
                    lng,
                },
            },
        },
        (error: Error, censusData: ICensusData) => {
            if (error) throw error;

            console.log("update user council district and congressional");
            console.log("census data response -", censusData);
            const newLocale = createLocale(currentLocale, Number(district));
            if (!newLocale) {
                console.error("CONGRESSIONAL UPDATE - NEW LOCALE IS VOID", newLocale);
                return;
            }
            const congressional =
                censusData?.geoHierarchy && censusData?.geoHierarchy["congressional district"];

            snap.ref
                .update({
                    isRegistrationComplete: true, // @ts-ignore
                    isSwayConfirmed: currentLocale.isSwayConfirmed, // @ts-ignore
                    isRegisteredToVote: currentLocale.isRegisteredToVote,
                    city: fromLocaleNameItem(newLocale.city),
                    region: fromLocaleNameItem(newLocale.region),
                    regionCode: fromLocaleNameItem(newLocale.regionCode),
                    country: fromLocaleNameItem(newLocale.country),
                    locale: firestoreConstructor.FieldValue.delete(),
                    locales: [newLocale, createLocale(CONGRESS_LOCALE, Number(congressional))],
                } as Partial<sway.IUser>)
                .catch(console.error);
        },
    ).catch(console.error);
};

const collectUsers = async (): Promise<QueryDocumentSnapshot[]> => {
    const query = firestore.collection(Collections.Users);
    const snap = await query.get();
    const docs = snap.docs
        .map((doc) => doc.data() as sway.IUser)
        .filter((user: sway.IUser) => isEmptyObject(user?.locales));

    if (!docs || docs.length === 0) return [];

    const query2 = firestore.collection(Collections.Users).where(
        "uid",
        "in",
        docs.map((u) => u.uid),
    );
    const snap2 = await query2.get();
    return snap2.docs;
};

export default async () => {
    console.log("Collecting users to update");
    const userSnaps = await collectUsers();
    console.log(`Found ${userSnaps.length} users to update.`);

    userSnaps.forEach(async (snap: QueryDocumentSnapshot) => {
        const user = snap.data() as sway.IUser;

        return geocodeOSM(user)
            .then((osmData) => {
                if (osmData && osmData.lat && osmData.lon) {
                    getUserCongressionalDistrict({
                        // @ts-ignore
                        currentLocale: user.locale,
                        lat: osmData.lat,
                        lng: osmData.lon,
                        snap,
                    });
                    return true;
                } else {
                    console.error("Geocode with OSM failed, trying Google.");
                    geocodeGoogle(user)
                        .then((googleData) => {
                            if (googleData && googleData.lat && googleData.lon) {
                                getUserCongressionalDistrict({
                                    // @ts-ignore
                                    localeName: user.locale.name,
                                    lat: googleData.lat,
                                    lng: googleData.lon,
                                    snap,
                                });
                                return true;
                            }
                        })
                        .catch(console.error);
                }
            })
            .catch(console.error);
    });
};
