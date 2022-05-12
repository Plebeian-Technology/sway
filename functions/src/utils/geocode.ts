import { BALTIMORE_CITY_LOCALE_NAME, CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import { findLocale, findNotCongressLocale, IS_DEVELOPMENT, toLocaleName } from "@sway/utils";
import * as turf from "@turf/turf";
import { Feature, FeatureCollection, Point, Properties } from "@turf/turf";
import * as functions from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import * as fs from "fs";
import fetch, { Response } from "node-fetch";
import { fire, sway } from "sway";
import { bucket } from "../firebase";
import { IFunctionsConfig, isEmptyObject } from "../utils";

const census = require("citysdk");

const { within, point } = turf;
const { logger } = functions;

const BASE_OSM_URL = "https://nominatim.openstreetmap.org/search";
const BASE_GOOGLE_URL = "https://maps.googleapis.com/maps/api/geocode/json";

export interface ICensusData {
    vintage: string; // ex. "2018"
    geoHierarchy: {
        state: string; // ex. "24"
        "congressional district": string; // ex. "03"
    };
}
export interface IGeocodeResponse {
    lat: number;
    lon: number;
    point: Feature<Point, Properties>;
}

export const createLocale = (localeName: string, district: string): sway.IUserLocale | void => {
    const locale = LOCALES.find((l: sway.ILocale) => l.name === localeName);
    if (!locale) return;

    return {
        ...locale,
        district: district,
    };
};

export const getLocaleGeojson = async (
    localeName: string,
): Promise<FeatureCollection | undefined> => {
    const destination = `/tmp/${localeName}.geojson`;

    try {
        logger.info(
            `geocode.getLocaleGeojson - Try getting geojson for locale from dynamic import - ${localeName}`,
        );
        // const geojson = await import(`../geojson/${localeName}.geojson`);
        const geojson = require(`../geojson/${localeName}.geojson`);
        if (geojson) {
            if (typeof geojson === "string") {
                logger.info(
                    `geocode.getLocaleGeojson - got geojson string for locale - ${localeName} - parse and return`,
                );
                return JSON.parse(geojson);
            } else {
                logger.info(
                    `geocode.getLocaleGeojson - got geojson object for locale - ${localeName} - return`,
                );
                return geojson;
            }
        }
    } catch (error) {
        logger.error(
            `geocode.getLocaleGeojson - Error getting geojson for locale from dynamic import - ${localeName}`,
        );
        logger.error(error);
    }

    return bucket
        .file(`geojsons/${localeName}.geojson`)
        .download({ destination })
        .then(() => JSON.parse(fs.readFileSync(destination, "utf-8")))
        .catch((error) => {
            logger.error(`Error getting geojson for locale from bucket - ${localeName}`, error);
        });
};

// NOTE: See test_census.js for example use
export const getUserCongressionalDistrict = async ({
    lat,
    lng,
    callback,
}: {
    lat: number;
    lng: number;
    callback: (
        error: Error,
        censusData: ICensusData,
        resolve: (value: sway.IUserLocale | undefined) => void,
    ) => void;
}): Promise<sway.IUserLocale | undefined> => {
    // eslint-disable-next-line
    return new Promise<sway.IUserLocale | undefined>((resolve, _reject) => {
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
            (error: Error, censusData: ICensusData) => callback(error, censusData, resolve),
        );
    }).then((success) => {
        logger.info(`geocode.getUserCongressionalDistrict - resolved successfully? ${success}`);
        return success;
    });
};

/*
 *
 * DEPRECATED METHODS BELOW
 *
 */

// * @deprecated
const geocodeOSM = async (doc: sway.IUser): Promise<IGeocodeResponse | undefined | void> => {
    if (IS_DEVELOPMENT) {
        logger.info("OSM Geocoding user - ", doc);
    }

    const address1 = doc.address1.toLowerCase();
    const city = doc.city.toLowerCase();
    const region = doc.region.toLowerCase();
    const country = doc.country.toLowerCase().replace("_", " ");
    const postalCode = doc.postalCode.toLowerCase();

    const url = `${BASE_OSM_URL}?street=${address1}&city=${city}&state=${region}&country=${country}&postalcode=${postalCode}&format=json&limit=1`;

    logger.info("URL 1 for OSM Locale Geocode", url);
    return fetch(url)
        .then((response) => {
            if (response && response.ok) {
                return response.json();
            } else {
                logger.warn("OSM geocode response NOT okay");
                logger.warn(response.status);
                logger.warn(response.statusText);
                return;
            }
        })
        .then((json: sway.IPlainObject | void) => {
            if (!json) {
                return logger.error("No json received from OSM geocode API for url: ", url);
            }

            const location = (json as any[])[0];
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
        });
};

// * @deprecated
const geocodeGoogle = async (
    doc: sway.IUser,
    config: IFunctionsConfig,
): Promise<IGeocodeResponse | undefined | void> => {
    if (IS_DEVELOPMENT) {
        logger.info("Google Geocoding user - ", doc);
    }

    logger.info("Geocoding Locale with Google");
    const apikey = config.geocode.apikey;
    if (!apikey) {
        logger.error("Could not resolve google api key from - functions.config().geocode.apikey");
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
        .then((response: Response) => {
            if (response && response.ok) {
                return response.json();
            } else {
                logger.warn("Google geocode response NOT okay");
                logger.warn(response.status);
                logger.warn(response.statusText);
                return;
            }
        })
        .then((json) => {
            if (!json) {
                logger.error("No json received from Google geocode API for address: ", address);
                return;
            } else {
                const location: { lat: number; lng: number } =
                    json && json.results && json.results[0] && json.results[0]?.geometry?.location;
                if (!location) {
                    logger.error("No geometry location in google json -", json);
                    return;
                } else {
                    return {
                        lat: location.lat,
                        lon: location.lng,
                        point: point([location.lng, location.lat]),
                    };
                }
            }
        })
        .catch((error: Error) => {
            logger.error("Error google geocoding address");
            logger.error(error);
        });
};

// * @deprecated
export const processUserGeoPoint = async (
    localeName: string,
    user: sway.IUser,
    snap: QueryDocumentSnapshot | fire.TypedDocumentSnapshot<sway.IUser>,
    features: Feature<any>[],
    geoData: IGeocodeResponse,
): Promise<sway.IUserLocale | undefined> => {
    const locale = findLocale(localeName);
    if (!locale) {
        logger.error(
            "geocode.processUserGeoPoint - Could not find locale from localeName, skipping processing user geo point -",
            localeName,
        );
        return;
    }

    const regionCode = locale.regionCode
        ? locale.regionCode.toUpperCase()
        : user.regionCode.toUpperCase();
    const withCode = (district: string | number) => {
        return `${regionCode.toUpperCase()}${district}`;
    };

    if (isEmptyObject(features)) {
        logger.error(
            "geocode.processUserGeoPoint - NO FEATURES for LOCALE - ",
            localeName,
            " - SKIP GETTING USER LOCALE DISTRICT. geoData -",
            geoData,
        );
        return;
    }

    logger.info(
        `geocode.processUserGeoPoint - Checking  - ${features.length} features in ${localeName} for user district`,
    );
    for (const feature of features) {
        const featureProperties = feature.properties;
        const isWithin = within(geoData.point, feature);
        if (!isWithin.features[0]) {
            logger.warn(
                "geocode.processUserGeoPoint - user geodata is not within feature, continuing",
            );
            continue;
        }

        logger.info(
            `geocode.processUserGeoPoint - geoData point is WITHIN feature. Finding district`,
        );
        const district =
            featureProperties?.area_name || featureProperties?.district || featureProperties?.Name; // BALTIMORE || LA || DC
        if (!district) {
            logger.error(
                "geocode.processUserGeoPoint - undefined district within coordinates, skipping user district update, feature properties below",
            );
            logger.error(featureProperties);
            continue;
        }

        logger.info(
            `geocode.processUserGeoPoint - found district - ${district} - from featureProperties`,
        );
        if (Number(district) === 0) {
            logger.error(
                "geocode.processUserGeoPoint - user district === 0, skipping user district update",
            );
            continue;
        }

        logger.info(
            "geocode.processUserGeoPoint - district is NOT 0. Getting congressional district and adding to user locales.",
        );
        return createLocale(localeName, withCode(Number(district))) || undefined;
    }

    logger.error(
        "geocode.processUserGeoPoint - Could not find user district from geodata, skipping locale district update and only updating congressional district. User geo data -",
        geoData,
        " - locale features -",
        features,
    );
    return;
};

// * @deprecated
export const processUserLocation = async (
    snap: QueryDocumentSnapshot,
    doc: sway.IUser,
    config: IFunctionsConfig,
): Promise<sway.IUser | null> => {
    const localeName = isEmptyObject(doc.locales)
        ? toLocaleName(doc.city, doc.region, doc.country)
        : findNotCongressLocale(doc.locales)?.name;
    const locale = findLocale(localeName || BALTIMORE_CITY_LOCALE_NAME);

    const localeGeojson = locale && (await getLocaleGeojson(localeName));
    if (!localeGeojson) {
        logger.warn(
            "geocode.processUserLocation - NO localeGeojson FOR LOCALE NAME -",
            localeName,
            "- ONLY GEOCODING FOR CONGRESS. Available LOCALES -",
            LOCALES,
        );
        return geocodeOSM(doc)
            .then(async (osmData) => {
                if (osmData && osmData.point) {
                    return processUserGeoPoint(CONGRESS_LOCALE_NAME, doc, snap, [], osmData).then(
                        (success) => {
                            if (success) {
                                return snap.data() as sway.IUser;
                            }
                            return null;
                        },
                    );
                } else {
                    return geocodeGoogle(doc, config).then(async (googleUserPoint) => {
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
                    });
                }
            })
            .catch((error) => {
                logger.error("Error geocoding for Congress locale", error);
                return null;
            });
    }

    logger.info("Running geocode with OSM");
    return geocodeOSM(doc).then(async (osmData) => {
        try {
            if (osmData && osmData.point) {
                const osmUser = await processUserGeoPoint(
                    localeName,
                    doc,
                    snap,
                    localeGeojson.features,
                    osmData,
                ).then(async (success) => {
                    if (success) {
                        const newSnap = await snap.ref.get();
                        return newSnap.data() as sway.IUser;
                    }
                    return null;
                });

                const newSnapOSM = await snap.ref.get();
                const updatedOSM = newSnapOSM.data() as sway.IUser;
                if (osmUser || updatedOSM.isRegistrationComplete) {
                    logger.info("OSM data is truthy, sending welcome email to user");
                    return updatedOSM;
                }
            }

            logger.error("Geocode with OSM failed, trying Google.");
            return await geocodeGoogle(doc, config).then(async (googleUserPoint) => {
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
                    logger.error("Geocode with Google failed. Failing user district lookup.");
                    return null;
                } catch (error) {
                    logger.error("Error Geocoding with Google -", error);
                    return null;
                }
            });
        } catch (error) {
            logger.error("Error Geocoding with OSM -", error);
            return null;
        }
    });
};
