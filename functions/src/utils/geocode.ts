import { LOCALES } from "@sway/constants";
import { Feature, FeatureCollection, Point, Properties } from "@turf/turf";
import * as functions from "firebase-functions";
import * as fs from "fs";
import { sway } from "sway";
import { bucket } from "../firebase";

const census = require("citysdk");

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
    const destination = `/tmp/${localeName}.geojson`;

    try {
        logger.info(
            `geocode.getLocaleGeojson - Try getting geojson for locale from dynamic import - ${localeName}`,
        );
        const geojson = await import(`../geojson/${localeName}.geojson`);
        // const geojson = require(`../geojson/${localeName}.geojson`);
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

    const filepath = `geojsons/${localeName}.geojson`;
    logger.info(
        `geocode.getLocaleGeojson - Bucket - ${bucket.name} - Filepath - ${filepath} - Destination - ${destination}. Getting geojson from bucket.`,
    );
    return bucket
        .file(filepath)
        .download({ destination })
        .then(() => JSON.parse(fs.readFileSync(destination, "utf-8")))
        .catch((error: any) => {
            logger.error(
                `geocode.getLocaleGeojson - Bucket - ${bucket.name} - Filepath - ${filepath} - Destination - ${destination}. ERROR GETTING ITEM FROM BUCKET -`,
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
        logger.info(`geocode.getUserCongressionalDistrict - resolved successfully? ${success}`);
        return success;
    });
};
