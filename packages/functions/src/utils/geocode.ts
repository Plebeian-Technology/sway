import {
    CONGRESS_LOCALE_NAME,
    LOCALES,
    WASHINGTON_DC_LOCALE_NAME,
} from "@sway/constants";
import { findLocale, toLocaleName } from "@sway/utils";
import * as turf from "@turf/turf";
import { Feature, FeatureCollection, Point, Properties } from "@turf/turf";
import * as functions from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import * as fs from "fs";
import fetch, { Response } from "node-fetch";
import { sway } from "sway";
import { bucket } from "../firebase";

const census = require("citysdk");

const { within, point } = turf;
const { logger } = functions;

const BASE_OSM_URL = "https://nominatim.openstreetmap.org/search";
const BASE_GOOGLE_URL = "https://maps.googleapis.com/maps/api/geocode/json";

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
    point: Feature<Point, Properties>;
}

const getLocaleGeojson = async (
    localeName: string,
): Promise<FeatureCollection | undefined> => {
    const destination = `/tmp/${localeName}.geojson`;

    return bucket
        .file(`geojsons/${localeName}.geojson`)
        .download({ destination })
        .then(() => {
            return JSON.parse(fs.readFileSync(destination, "utf8"));
        })
        .catch((error) => {
            logger.error(
                `Error getting geojson for locale - ${localeName}`,
                error,
            );
            return;
        });
};

const geocodeOSM = async (
    doc: sway.IUser,
): Promise<IGeocodeResponse | undefined | void> => {
    const url = `${BASE_OSM_URL}?street=${doc.address1.toLowerCase()}&city=${doc.city.toLowerCase()}&state=${doc.region.toLowerCase()}&country=${doc.country.toLowerCase()}&postalcode=${
        doc.postalCode
    }&format=json&limit=1`;

    logger.info("URL 1 for OSM Geocode", url);
    return fetch(url)
        .then((response: Response) => {
            if (response && response.ok) return response.json();
            logger.warn("OSM geocode response NOT okay");
            logger.warn(response.status);
            logger.warn(response.statusText);
            return;
        })
        .then((json: sway.IPlainObject) => {
            if (!json) {
                return logger.error(
                    "No json received from OSM geocode API for url: ",
                    url,
                );
            }

            const location = json[0];
            if (!location) {
                return logger.error("no location from OSM json ->", json);
            }
            return {
                lat: location.lat,
                lon: location.lon,
                point: point([location.lon, location.lat]),
            };
        })
        .catch((error: Error) => {
            logger.error("Error geocoding address with OSM");
            logger.error(error);
            return;
        });
};

const geocodeGoogle = async (
    doc: sway.IUser,
    config: sway.IPlainObject,
): Promise<IGeocodeResponse | undefined | void> => {
    logger.info("Geocoding with Google");
    const apikey = config.geocode.apikey;
    if (!apikey) {
        logger.error(
            "Could not resolve google api key from - functions.config().geocode.apikey",
        );
        return;
    }
    const address = `${doc.address1}${
        doc.address2 ? " " + doc.address2 : ""
    }, ${doc.city}, ${doc.region} ${doc.postalCode}`;
    const url = `${BASE_GOOGLE_URL}?address=${address}&key=${apikey}`;
    return fetch(url)
        .then((response: Response) => {
            if (response && response.ok) return response.json();
            logger.warn("Google geocode response NOT okay");
            logger.warn(response.status);
            logger.warn(response.statusText);
            return;
        })
        .then((json: sway.IPlainObject) => {
            if (!json) {
                return logger.error(
                    "No json received from Google geocode API for address: ",
                    address,
                );
            }

            const location: { lat: number; lng: number } =
                json &&
                json.results &&
                json.results[0] &&
                json.results[0]?.geometry?.location;
            if (!location) {
                logger.info(json);
                return logger.error("No geometry location in google json");
            }

            return {
                lat: location.lat,
                lon: location.lng,
                point: point([location.lng, location.lat]),
            };
        })
        .catch((error: Error) => {
            logger.error("Error google geocoding address");
            logger.error(error);
            return;
        });
};

// NOTE: See test_census.js for example use
const getUserCongressionalDistrict = ({
    lat,
    lng,
    callback,
}: {
    lat: number;
    lng: number;
    callback: (
        error: Error,
        censusData: ICensusData,
        resolve: (value: boolean) => void,
    ) => void;
}) => {
    return new Promise((resolve, reject) => {
        census(
            {
                vintage: 2019,
                geoHierarchy: {
                    "congressional district": {
                        lat,
                        lng,
                    },
                },
            },
            (error: Error, censusData: ICensusData) =>
                callback(error, censusData, resolve),
        );
    });
};

const processUserGeoPoint = async (
    localeName: string,
    user: sway.IUser,
    snap: QueryDocumentSnapshot,
    features: Feature<any>[],
    geoData: IGeocodeResponse,
): Promise<boolean> => {
    const locale = LOCALES.find((l: sway.ILocale) => l.name === localeName);
    if (!locale) {
        logger.error(
            "Could not find locale from localeName, skipping processing user geo point -",
            localeName,
        );
        return false;
    }

    const regionCode = locale.regionCode
        ? locale.regionCode.toUpperCase()
        : user.regionCode.toUpperCase();
    const withCode = (district: string | number) => {
        return `${regionCode.toUpperCase()}${district}`;
    };

    if (localeName === CONGRESS_LOCALE_NAME) {
        return getUserCongressionalDistrict({
            lat: geoData.lat,
            lng: geoData.lon,
            callback: (
                error: Error,
                censusData: ICensusData,
                resolve: (value: boolean) => void,
            ) => {
                if (error) {
                    resolve(false);
                    return false;
                }

                logger.info(
                    `update user congressional census data response -`,
                    censusData,
                );
                const congressional =
                    censusData?.geoHierarchy &&
                    censusData?.geoHierarchy["congressional district"];

                return snap.ref
                    .update({
                        isRegistrationComplete: true,
                        locales: [
                            createLocale(
                                CONGRESS_LOCALE_NAME,
                                withCode(Number(congressional)),
                            ),
                        ],
                    } as Partial<sway.IUser>)
                    .then(() => {
                        resolve(true);
                        return true;
                    })
                    .catch((err) => {
                        logger.error(err);
                        resolve(false);
                        return false;
                    });
            },
        }) as Promise<boolean>;
    }
    for (let index = 0; index < features.length; index++) {
        let feature = features[index];
        let featureProperties = feature.properties;
        let isWithin = within(geoData.point, feature);
        if (!isWithin.features[0]) {
            logger.warn("user geodata is not within feature, continuing");
            continue;
        }

        let district =
            featureProperties?.area_name ||
            featureProperties?.district ||
            featureProperties?.Name; // BALTIMORE || LA || DC
        if (!district) {
            logger.error(
                "undefined district within coordinates, skipping user district update, feature properties below",
            );
            logger.error(featureProperties);
            continue;
        }
        if (Number(district) === 0) {
            logger.error("user district === 0, skipping user district update");
            continue;
        }

        return getUserCongressionalDistrict({
            lat: geoData.lat,
            lng: geoData.lon,
            callback: (
                error: Error,
                censusData: ICensusData,
                resolve: (value: boolean) => void,
            ) => {
                if (error) {
                    resolve(false);
                    return false;
                }

                logger.info(
                    `update user council district - ${district} - and congressional census data response -`,
                    censusData,
                );
                const congressional =
                    localeName === WASHINGTON_DC_LOCALE_NAME
                        ? 0
                        : censusData?.geoHierarchy &&
                          censusData?.geoHierarchy["congressional district"];

                return snap.ref
                    .update({
                        isRegistrationComplete: true,
                        locales: [
                            createLocale(
                                localeName,
                                withCode(Number(district)),
                            ),
                            createLocale(
                                CONGRESS_LOCALE_NAME,
                                withCode(Number(congressional)),
                            ),
                        ],
                    } as Partial<sway.IUser>)
                    .then(() => {
                        resolve(true);
                        return true;
                    })
                    .catch((err) => {
                        logger.error(err);
                        resolve(false);
                        return false;
                    });
            },
        }) as Promise<boolean>;
    }

    logger.error(
        "Could not find user district from geodata, skipping local district update and only updating congressional district. User geo data -",
        geoData,
    );
    return false;
};

const createLocale = (
    localeName: string,
    district: string,
): sway.IUserLocale | void => {
    const locale = LOCALES.find((l: sway.ILocale) => l.name === localeName);
    if (!locale) return;

    return {
        ...locale,
        district: district,
    };
};

export const processUserLocation = async (
    snap: QueryDocumentSnapshot,
    doc: sway.IUser,
    config: sway.IPlainObject,
): Promise<sway.IUser | null> => {
    const localeName = toLocaleName(doc.city, doc.region, doc.country);
    const locale = findLocale(localeName);

    const localeGeojson = locale && (await getLocaleGeojson(localeName));
    if (!localeGeojson) {
        return geocodeOSM(doc)
            .then(async (osmData) => {
                if (osmData && osmData.point) {
                    return processUserGeoPoint(
                        CONGRESS_LOCALE_NAME,
                        doc,
                        snap,
                        [],
                        osmData,
                    ).then((success) => {
                        if (success) {
                            return snap.data() as sway.IUser;
                        }
                        return null;
                    });
                } else {
                    return geocodeGoogle(doc, config).then(
                        async (googleUserPoint) => {
                            if (googleUserPoint) {
                                return processUserGeoPoint(
                                    CONGRESS_LOCALE_NAME,
                                    doc,
                                    snap,
                                    [],
                                    googleUserPoint,
                                ).then(async (success) => {
                                    if (success) {
                                        const newSnap = await snap.ref.get();
                                        return newSnap.data() as sway.IUser;
                                    }
                                    return null;
                                });
                            }
                            return null;
                        },
                    );
                }
            })
            .catch((error) => {
                logger.error("Error geocoding for Congress locale", error);
                return null;
            });
    }

    logger.info("Running geocode with OSM");
    return await geocodeOSM(doc).then(async (osmData) => {
        try {
            const osm =
                osmData &&
                osmData.point &&
                (await processUserGeoPoint(
                    localeName,
                    doc,
                    snap,
                    localeGeojson.features,
                    osmData,
                ));

            const newSnapOSM = await snap.ref.get();
            const updatedOSM = newSnapOSM.data() as sway.IUser;
            if (osm || updatedOSM.isRegistrationComplete) {
                logger.info("Sending welcome email to user");
                return updatedOSM;
            }

            logger.error("Geocode with OSM failed, trying Google.");
            return await geocodeGoogle(doc, config).then(
                async (googleUserPoint) => {
                    try {
                        const google =
                            googleUserPoint &&
                            (await processUserGeoPoint(
                                localeName,
                                doc,
                                snap,
                                localeGeojson.features,
                                googleUserPoint,
                            ));

                        const newSnapGoogle = await snap.ref.get();
                        const updatedGoogle = newSnapGoogle.data() as sway.IUser;
                        if (google || updatedGoogle.isRegistrationComplete) {
                            logger.info("Sending welcome email to user");
                            return updatedGoogle;
                        }
                        logger.error(
                            "Geocode with Google failed. Failing user district lookup.",
                        );
                        return null;
                    } catch (error) {
                        logger.error("Error Geocoding with Google -", error);
                        return null;
                    }
                },
            );
        } catch (error) {
            logger.error("Error Geocoding with OSM -", error);
            return null;
        }
    });
};
