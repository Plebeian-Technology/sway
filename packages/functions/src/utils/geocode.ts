import * as turf from "@turf/turf";
import { Feature, Point } from "@turf/turf";
import * as functions from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import * as fs from "fs";
import fetch, { Response } from "node-fetch";
import { sway } from "sway";

const { within, point } = turf;
const { logger } = functions;

const BASE_GEOJSON_PATH = `${__dirname}/../../geojson`;
const BASE_OSM_URL = "https://nominatim.openstreetmap.org/search";
const BASE_GOOGLE_URL = "https://maps.googleapis.com/maps/api/geocode/json";

const GEOJSON_FILE_PATHS: string[] = fs
    .readdirSync(BASE_GEOJSON_PATH)
    .map((filename: string) => {
        if (!filename.endsWith(".geojson")) return null;

        return `${BASE_GEOJSON_PATH}/${filename}`;
    })
    .filter(Boolean) as string[];

const getLocaleGeojson = (localeName: string) => {
    const data = GEOJSON_FILE_PATHS.reduce((sum, path: string) => {
        if (!path.includes(localeName)) return sum;

        const filename = path.replace(`${BASE_GEOJSON_PATH}/`, "");
        const name = filename.split(".")[0];
        if (!name) return sum;

        // @ts-ignore
        sum[name] = JSON.parse(fs.readFileSync(path));
        return sum;
    }, {} as { [key: string]: sway.IPlainObject });

    if (data[localeName]) return data;

    logger.error("NO GEOJSON DATA FOR LOCALE -", localeName);
    logger.error("DIR", __dirname);
    logger.error("KEYS", Object.keys(data));
    logger.error("PATHS", GEOJSON_FILE_PATHS);
    return;
};

const geocodeOSM = async (doc: sway.IUser) => {
    const url = `${BASE_OSM_URL}?street=${doc.address1.toLowerCase()}&city=${doc.city.toLowerCase()}&state=${doc.region.toLowerCase()}&country=${doc.country.toLowerCase()}&postalcode=${
        doc.postalCode
    }&format=json&limit=1`;

    logger.info("URL 1 for OSM Geocode", url);
    return fetch(url)
        .then((response: Response) => {
            if (response && response.ok) return response.json();
            logger.warn("geocode response NOT okay");
            logger.warn(response.status);
            logger.warn(response.statusText);
            throw new Error("Bad response from OSM Geocoding API");
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
            return point([location.lon, location.lat]);
        })
        .catch((error: Error) => {
            logger.error("Error geocoding address with OSM");
            logger.error(error);
            throw error;
        });
};

const geocodeGoogle = async (doc: sway.IUser) => {
    logger.info("Geocoding with Google");
    const address = `${doc.address1}${
        doc.address2 ? " " + doc.address2 : ""
    }, ${doc.city}, ${doc.region} ${doc.postalCode}`;
    return fetch(
        `${BASE_GOOGLE_URL}?address=${address}&key=${
            functions.config().geocode.apikey
        }`,
    )
        .then((response: Response) => {
            if (response && response.ok) return response.json();
            logger.warn("Google geocode response NOT okay");
            logger.warn(response.status);
            logger.warn(response.statusText);
            throw new Error("Bad response from Google Geocoding API");
        })
        .then((json: sway.IPlainObject) => {
            if (!json)
                throw new Error(
                    "no json received from Google geocode API for address: " +
                        address,
                );

            const location =
                json &&
                json.results &&
                json.results[0] &&
                json.results[0]?.geometry?.location;
            if (!location) {
                logger.info(json);
                logger.error("No geometry location in google json");
                return false;
            }
            return point([location.lng, location.lat]);
        })
        .catch((error: Error) => {
            logger.error("Error google geocoding address");
            logger.error(error);
            throw error;
        });
};

const processUserGeoPoint = (
    snap: QueryDocumentSnapshot,
    features: Feature<any>[],
    userGeoPoint: Feature<Point>,
): boolean => {
    for (let index = 0; index < features.length; index++) {
        let feature = features[index];
        let featureProperties = feature.properties;
        let isWithin = within(userGeoPoint, feature);
        if (!isWithin.features[0]) continue;

        let district = featureProperties?.area_name || featureProperties?.Name;
        if (!district) {
            logger.error(
                "undefined district within coordinates, skipping user district update, feature properties below",
            );
            logger.error(featureProperties)
            continue;
        }
        if (Number(district) === 0) {
            logger.error("user district === 0, skipping user district update");
            continue;
        }

        logger.info("updating user with new district");
        snap.ref.update({
            isRegistrationComplete: true,
            "locale.district": Number(district),
        } as Partial<sway.IUser>);
        return true;
    }
    return false;
};

export const processUserLocation = async (
    snap: QueryDocumentSnapshot,
    doc: sway.IUser,
): Promise<boolean> => {
    const localeName = doc.locale?.name;
    if (!localeName) {
        logger.error(
            "User has no locale name after insert. Locale - ",
            doc.locale,
        );
        return false;
    }

    const localeGeojson = getLocaleGeojson(localeName);
    if (!localeGeojson) {
        return false;
    }

    logger.info("Running geocode with OSM");
    return geocodeOSM(doc).then((osmUserPoint) => {
        const osm =
            osmUserPoint &&
            processUserGeoPoint(
                snap,
                localeGeojson[localeName].features,
                osmUserPoint,
            );
        if (osm || snap.data().isRegistrationComplete) {
            logger.info("Sending welcome email to user");
            return true;
        }

        logger.error("Geocode with OSM failed, trying Google.");
        return geocodeGoogle(doc).then((googleUserPoint) => {
            const google =
                googleUserPoint &&
                processUserGeoPoint(
                    snap,
                    localeGeojson[localeName].features,
                    googleUserPoint,
                );
            if (google || snap.data().isRegistrationComplete) {
                logger.info("Sending welcome email to user");
                return true;
            }
            logger.error(
                "Geocode with Google failed. Failing user district lookup.",
            );
            return false;
        });
    });
};
