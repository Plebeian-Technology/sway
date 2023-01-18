import {
    CONGRESS,
    CONGRESS_LOCALE_NAME,
    ELocaleName,
    LOCALES,
    LOCALE_GEOJSON_FEATURE_COUNCIL_DISTRICT_KEY,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject } from "@sway/utils";
import { Feature, point, Point, Properties, within } from "@turf/turf";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/v1/https";

import get from "lodash.get";
import { sway } from "sway";
import { db, firestoreConstructor } from "../firebase";
import { createLocale, getLocaleGeojson, getUserCongressionalDistrict } from "../utils/geocode";

const { logger } = functions;

export interface IGeocodeResponse {
    lat: number;
    lon: number;
    point: Feature<Point, Properties>;
}

interface IData extends Partial<sway.IBill> {
    uid: string;
    locale: sway.IUserLocale;
    lat: number;
    lng: number;
}

const withCode = (user: sway.IUser, district: string | number) => {
    return `${user.regionCode.toUpperCase()}${district}`;
};

export const createUserLegislators = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<sway.IUser | null> => {
        logger.info("createUserLegislators - called");
        if (!context?.auth?.uid) {
            logger.error(
                "createUserLegislators - no uid in context.auth.uid. Skip creating user legislators.",
            );
            return null;
        }
        if (context?.auth?.uid !== data?.uid) {
            logger.error(
                "createUserLegislators - auth uid does not match data uid. Skip creating user legislators.",
            );
            return null;
        }
        const { uid } = context.auth;

        const client = new SwayFireClient(db, null, firestoreConstructor, logger);
        const user = await client.users(uid).getWithoutSettings();
        if (!user) {
            return null;
        }
        const snap = await client.users(uid).snapshot();
        if (!snap) {
            return null;
        }

        const locales = [] as sway.IUserLocale[];
        const congress = await getCongressionalDistrict(user, data.lat, data.lng);
        if (congress) {
            locales.push(congress);
        }

        const localeGeojson = data.locale && (await getLocaleGeojson(data.locale.name));
        if (localeGeojson) {
            const userLocale = await getUserLocale(data.locale, user, localeGeojson.features, {
                lat: data.lat,
                lon: data.lng,
                point: point([data.lng, data.lat]),
            } as IGeocodeResponse);
            if (userLocale) {
                logger.info(
                    `createUserLegislators - userLocale CREATED with district - ${userLocale.district}. Update user with BOTH userLocale and congress locale.`,
                );
                locales.push(userLocale);
                return updateUserLocales(uid, user, userLocale, locales);
            }
        } else {
            logger.warn(
                `createUserLegislators - NO localeGeojson FOR LOCALE NAME - ${data.locale.name} - ONLY GEOCODING FOR CONGRESS. Available LOCALES -`,
                LOCALES,
            );
        }

        if (!congress) {
            logger.error(
                "createUserLegislators - NEITHER congress NOR userLocale CREATED. Skip updating user locales.",
            );
            return null;
        } else {
            logger.info(
                "createUserLegislators - NO userLocale created. Update user with ONLY congress locale.",
            );
            return updateUserLocales(uid, user, congress, locales);
        }
    },
);

const updateUserLocales = async (
    uid: string,
    user: sway.IUser,
    clientLocale: sway.IUserLocale,
    userLocales: sway.IUserLocale[],
) => {
    const client = new SwayFireClient(db, clientLocale, firestoreConstructor, logger);
    return client
        .users(uid)
        .update({
            ...user,
            locales: userLocales,
        })
        .then(async () => {
            await updateLocaleUsersCount(client, userLocales).catch((e) => {
                logger.error(e);
                return null;
            });
            return client
                .users(uid)
                .getWithoutSettings()
                .then((u) => {
                    return u || null;
                })
                .catch((e) => {
                    logger.error(e);
                    return null;
                });
        })
        .catch((e) => {
            logger.error(e);
            return null;
        });
};

const updateLocaleUsersCount = async (client: SwayFireClient, locales: sway.IUserLocale[]) => {
    for (const locale of locales) {
        const usersInLocale = await client.locales().get(locale);
        if (usersInLocale) {
            await client
                .locales()
                .addUserToCount(usersInLocale, locale.district, {
                    addToAll: locale.name !== CONGRESS_LOCALE_NAME,
                })
                .then((newLocale) => {
                    logger.info("Updated locale user count -", newLocale);
                })
                .catch(logger.error);
        }
    }
};

const getUserLocale = async (
    locale: sway.ILocale,
    user: sway.IUser,
    features: Feature<any>[],
    geoData: IGeocodeResponse,
): Promise<sway.IUserLocale | undefined> => {
    if (isEmptyObject(features)) {
        logger.error(
            "createUserLegislators.getUserLocale - NO FEATURES for LOCALE - ",
            locale.name,
            " - SKIP GETTING USER LOCALE DISTRICT. geoData -",
            geoData,
        );
        return;
    }

    logger.info(
        `createUserLegislators.getUserLocale - Checking  - ${features.length} features in ${locale.name} for user district`,
    );
    for (const feature of features) {
        const featureProperties = feature.properties;
        const isWithin = within(geoData.point, feature);
        if (!isWithin.features[0]) {
            logger.warn(
                "createUserLegislators.getUserLocale - user geodata is not within feature, continuing",
            );
            continue;
        }

        logger.info(
            `createUserLegislators.getUserLocale - geoData point is WITHIN feature. Finding district`,
        );
        const district = (() => {
            let d = get(
                featureProperties,
                LOCALE_GEOJSON_FEATURE_COUNCIL_DISTRICT_KEY[locale.name as ELocaleName],
            );
            if (!d) {
                d =
                    featureProperties?.area_name ||
                    featureProperties?.district ||
                    featureProperties?.Name ||
                    featureProperties?.CONGR_DIST; // BALTIMORE CONGRESSIONAL || LA || DC
            }
            return d;
        })();

        if (!district) {
            logger.error(
                "createUserLegislators.getUserLocale - undefined district within coordinates, skipping user district update, feature properties below",
            );
            logger.error(featureProperties);
            continue;
        }

        logger.info(
            `createUserLegislators.getUserLocale - found district - ${district} - from featureProperties`,
        );
        if (Number(district) === 0) {
            logger.error(
                "createUserLegislators.getUserLocale - user district === 0, skipping user district update",
            );
            continue;
        }

        const districtWithCode = withCode(user, Number(district));
        logger.info(
            `createUserLegislators.getUserLocale - district is NOT 0. Returning locale with district - ${districtWithCode} - added.`,
        );
        return createLocale(locale.name, districtWithCode) || undefined;
    }

    logger.error(
        `createUserLegislators.getUserLocale - Could not find user district from geodata, skipping locale district update and only updating congressional district. User geo data - ${geoData} - locale features - ${features}`,
    );
    return;
};

const getCongressionalDistrict = async (
    user: sway.IUser,
    lat: number,
    lng: number,
): Promise<sway.IUserLocale | undefined> => {
    return getUserCongressionalDistrict({
        lat: lat,
        lng: lng,
    })
        .then((censusData) => {
            if (!censusData) return undefined;

            const congressional = censusData?.features?.first()?.attributes[`CD${CONGRESS}`];
            logger.info(
                `getUserCongressionalDistrict - update user congressional census data response -`,
                { congressional },
                // censusData,
            );
            // const congressional = censusData?.geoHierarchy && censusData?.geoHierarchy["congressional district"];

            if (!congressional) {
                logger.error(
                    "getUserCongressionalDistrict - no congressional district found in censusData -",
                    censusData,
                );
                return undefined;
            }

            const created = createLocale(
                CONGRESS_LOCALE_NAME,
                withCode(user, Number(congressional)),
            ) as sway.IUserLocale;

            if (!created) {
                logger.error(
                    "getUserCongressionalDistrict - no locale created/congressional -",
                    created,
                    congressional,
                );
                return undefined;
            } else {
                return created;
            }
        })
        .catch((e) => {
            logger.error(e);
            return undefined;
        });
};
// getUserCongressionalDistrict({
//     lat: lat,
//     lng: lng,
//     callback: (
//         error: Error,
//         censusData: ICensusSDKData,
//         resolve: (value: sway.IUserLocale | undefined) => void,
//     ) => {
//         const fail = () => {
//             resolve(undefined);
//             return;
//         };

//         if (error) {
//             logger.error(error);
//             return fail();
//         }

//         logger.info(
//             `getUserCongressionalDistrict - update user congressional census data response -`,
//             censusData,
//         );
//         const congressional =
//             censusData?.geoHierarchy && censusData?.geoHierarchy["congressional district"];
//         if (!congressional) {
//             logger.error(
//                 "getUserCongressionalDistrict - no congressional district found in censusData -",
//                 censusData,
//             );
//             return fail();
//         }

//         const created = createLocale(
//             CONGRESS_LOCALE_NAME,
//             withCode(user, Number(congressional)),
//         ) as sway.IUserLocale;

//         if (!created) {
//             logger.error(
//                 "getUserCongressionalDistrict - no locale created/congressional -",
//                 created,
//                 congressional,
//             );
//             fail();
//         } else {
//             resolve(created);
//         }
//     },
// });
