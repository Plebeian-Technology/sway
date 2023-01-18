import { FeatureCollection } from "@turf/turf";
import * as functions from "firebase-functions";
import * as fs from "fs";
import { sway } from "sway";
import { CONGRESS, CONGRESS_LOCALE_NAME, LOCALES } from "../../constants";
import { bucket } from "../firebase";

// @ts-ignore
// const census = (...args) => import("citysdk").then(({ default: census }) => census(...args)); // eslint-disable-line
// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line
// import census from 'citysdk'

const CENSUS_QUERY_URL = `https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2022/MapServer/50/query?geometry=<longitude>,<latitude>&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD${CONGRESS}`;
// const CENSUS_QUERY_URL = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2022/MapServer/50?geometry=<latitude>,<longitude>&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=false&f=json&outFields=STATE,CD118"
const getCensusQueryUrl = (latitude: number, longitude: number) => {
    return CENSUS_QUERY_URL.replace("<latitude>", latitude.toString()).replace(
        "<longitude>",
        longitude.toString(),
    );
};

const { logger } = functions;

export interface ICensusSDKData {
    // vintages:
    // https://github.com/uscensusbureau/citysdk/tree/master/v2/GeoJSON/500k
    // https://uscensusbureau.github.io/citysdk/docs/#geographies-available-by-vintage
    vintage: string; // ex. "2018"
    geoHierarchy: {
        state: string; // ex. "24"
        "congressional district": string; // ex. "03"
    };
}
export interface ICensusAPIData {
    displayFieldName: string;
    fieldAliases: { STATE: "STATE"; CD118: "CD118" };
    geometryType: "esriGeometryPolygon";
    spatialReference: { wkid: number; latestWkid: number };
    fields: [
        {
            name: "STATE";
            type: "esriFieldTypeString";
            alias: "STATE";
            length: 2;
        },
        {
            name: "CD118";
            type: "esriFieldTypeString";
            alias: "CD118";
            length: 2;
        },
    ];
    features: [
        {
            attributes: { STATE: string; CD118?: string; CD117?: string; CD116?: string };
            geometry: {
                rings: [number, number][][];
            };
        },
    ];
}

export const createLocale = (localeName: string, district: string): sway.IUserLocale | void => {
    const locale = LOCALES.find(
        (l: sway.ILocale) => l.name.toLowerCase() === localeName?.toLowerCase(),
    );
    if (!locale) {
        logger.info(`Could not find localeName - ${localeName} in LOCALES`, LOCALES);
        return;
    } else {
        return {
            ...locale,
            district: district,
        };
    }
};

export const getLocaleGeojson = async (
    localeName: string,
): Promise<FeatureCollection | undefined> => {
    if (localeName === CONGRESS_LOCALE_NAME) {
        logger.info(
            `geocode.getLocaleGeojson - localeName - ${localeName} - No congress geojson available. Skip getting geojson.`,
        );
        return;
    }

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
}: // callback,
{
    lat: number;
    lng: number;
    // callback: (
    //     error: Error,
    //     censusData: ICensusSDKData,
    //     resolve: (value: sway.IUserLocale | undefined) => void,
    // ) => void;
}): Promise<ICensusAPIData | undefined> => {
    return fetch(getCensusQueryUrl(lat, lng))
        .then((response) => {
            return response.json();
        })
        .then((json) => {
            return json as ICensusAPIData;
        })
        .catch((e) => {
            logger.error(e);
            return undefined;
        });

    // return new Promise<sway.IUserLocale | undefined>((resolve) => {
    //     census(
    //         {
    //             // https://uscensusbureau.github.io/citysdk/docs/#geographies-available-by-vintage
    //             // https://github.com/uscensusbureau/citysdk/tree/master/v2/GeoJSON/500k
    //             vintage: 2021,
    //             geoHierarchy: {
    //                 "congressional district": {
    //                     lat,
    //                     lng,
    //                 },
    //             },
    //         },
    //         (error: Error, censusData: ICensusSDKData) => callback(error, censusData, resolve),
    //     ).catch(logger.error);
    // }).then((success) => {
    //     logger.info(`geocode.getUserCongressionalDistrict - resolved successfully?`);
    //     logger.info({ success });
    //     return success;
    // });
};
