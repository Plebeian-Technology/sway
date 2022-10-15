import { LOCALES } from "../../constants";
import { Feature, FeatureCollection, Point, Properties } from "@turf/turf";
import * as functions from "firebase-functions";
import * as fs from "fs";
import { sway } from "sway";
import { bucket } from "../firebase";

// @ts-ignore
const census = (...args) => import("citysdk").then(({ default: census }) => census(...args));

const { logger } = functions;

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
    const destination = `/tmp/${localeName}.json`;

    try {
        logger.info(
            `geocode.getLocaleGeojson - Try getting geojson for locale from dynamic import - ../../geojson/2020/${localeName}.json`,
        );
        const geojson = await import(`../../geojson/2020/${localeName}.json`, {
            assert: { type: "json" },
        });
        // const geojson = require(`../geojson/${localeName}.json`);
        if (geojson) {
            if (typeof geojson === "string") {
                logger.info(
                    `geocode.getLocaleGeojson - got geojson string for locale - ${localeName} - parse and return`,
                );
                // Remove all newline characters and whitespace
                const geo = JSON.parse(geojson.replace(/[\n\r]/g, "").replace(/\s+/g, ""));
                if ("default" in geo) {
                    return geo.default;
                } else {
                    return geo;
                }
            } else {
                logger.info(
                    `geocode.getLocaleGeojson - got geojson object for locale - ${localeName} - return`,
                );
                if ("default" in geojson) {
                    return geojson.default;
                } else {
                    return geojson;
                }
            }
        }
    } catch (error) {
        logger.error(
            `geocode.getLocaleGeojson - Error getting geojson for locale from dynamic import - ${localeName}`,
        );
        logger.error(error);
    }

    const bucketFilepath = `geojsons/${localeName}.geojson`;
    logger.info(
        `geocode.getLocaleGeojson - Bucket - ${bucket.name} - Filepath - ${bucketFilepath} - Destination - ${destination}. Getting geojson from bucket.`,
    );
    return bucket
        .file(bucketFilepath)
        .download({ destination })
        .then(() => JSON.parse(fs.readFileSync(destination, "utf-8")))
        .catch((error: any) => {
            logger.error(
                `geocode.getLocaleGeojson - Bucket - ${bucket.name} - Filepath - ${bucketFilepath} - Destination - ${destination}. ERROR GETTING ITEM FROM BUCKET -`,
                error,
            );
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
        logger.info(`geocode.getUserCongressionalDistrict - resolved successfully?`);
        logger.info({ success });
        return success;
    });
};
