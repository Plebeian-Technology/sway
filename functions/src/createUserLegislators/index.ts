import { CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject } from "@sway/utils";
import { Feature, point, within } from "@turf/turf";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import {
    createLocale,
    getLocaleGeojson,
    getUserCongressionalDistrict,
    ICensusData,
    IGeocodeResponse,
} from "../utils/geocode";

const { logger } = functions;

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
        if (!context?.auth?.uid) {
            return null;
        }
        if (context?.auth?.uid !== data?.uid) {
            logger.error("auth uid does not match data uid, skipping user sway aggregation");
            return null;
        }
        const { uid } = context.auth;

        const client = new SwayFireClient(db, null, firestore);
        const user = await client.users(uid).getWithoutSettings();
        if (!user) {
            return null;
        }
        const snap = await client.users(uid).snapshot();
        if (!snap) {
            return null;
        }

        const locales = [] as sway.IUserLocale[];
        logger.warn(
            "geocode.processUserLocation - NO localeGeojson FOR LOCALE NAME -",
            data.locale.name,
            "- ONLY GEOCODING FOR CONGRESS. Available LOCALES -",
            LOCALES,
        );
        const congress = await getCongressionalDistrict(user, data.lat, data.lng);
        if (congress) {
            locales.push(congress);
        }

        const localeGeojson = data.locale && (await getLocaleGeojson(data.locale.name));
        if (localeGeojson) {
            const userLocale = await getUserLocale(data.locale, user, [], {
                lat: data.lat,
                lon: data.lng,
                point: point([data.lng, data.lat]),
            } as IGeocodeResponse);
            if (userLocale) {
                locales.push(userLocale);
            }
        }

        return client
            .users(uid)
            .update({
                ...user,
                locales: [...user.locales, ...locales],
            })
            .then(async () => {
                await updateLocaleWithUser(client, locales).catch((e) => {
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
    },
);

const updateLocaleWithUser = async (client: SwayFireClient, locales: sway.IUserLocale[]) => {
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
            "geocode.getUserLocale - NO FEATURES for LOCALE - ",
            locale.name,
            " - SKIP GETTING USER LOCALE DISTRICT. geoData -",
            geoData,
        );
        return;
    }

    logger.info(
        `geocode.getUserLocale - Checking  - ${features.length} features in ${locale.name} for user district`,
    );
    for (const feature of features) {
        const featureProperties = feature.properties;
        const isWithin = within(geoData.point, feature);
        if (!isWithin.features[0]) {
            logger.warn("geocode.getUserLocale - user geodata is not within feature, continuing");
            continue;
        }

        logger.info(`geocode.getUserLocale - geoData point is WITHIN feature. Finding district`);
        const district =
            featureProperties?.area_name || featureProperties?.district || featureProperties?.Name; // BALTIMORE || LA || DC
        if (!district) {
            logger.error(
                "geocode.getUserLocale - undefined district within coordinates, skipping user district update, feature properties below",
            );
            logger.error(featureProperties);
            continue;
        }

        logger.info(
            `geocode.getUserLocale - found district - ${district} - from featureProperties`,
        );
        if (Number(district) === 0) {
            logger.error(
                "geocode.getUserLocale - user district === 0, skipping user district update",
            );
            continue;
        }

        logger.info(
            "geocode.getUserLocale - district is NOT 0. Getting congressional district and adding to user locales.",
        );
        return createLocale(locale.name, withCode(user, Number(district))) || undefined;
    }

    logger.error(
        "geocode.getUserLocale - Could not find user district from geodata, skipping locale district update and only updating congressional district. User geo data -",
        geoData,
        " - locale features -",
        features,
    );
    return;
};

const getCongressionalDistrict = async (
    user: sway.IUser,
    lat: number,
    lng: number,
): Promise<sway.IUserLocale | undefined> =>
    getUserCongressionalDistrict({
        lat: lat,
        lng: lng,
        callback: (
            error: Error,
            censusData: ICensusData,
            resolve: (value: sway.IUserLocale | undefined) => void,
        ) => {
            const fail = () => {
                resolve(undefined);
                return;
            };

            if (error) {
                logger.error(error);
                return fail();
            }

            logger.info(
                `getUserCongressionalDistrict - update user congressional census data response -`,
                censusData,
            );
            const congressional =
                censusData?.geoHierarchy && censusData?.geoHierarchy["congressional district"];
            if (!congressional) {
                logger.error(
                    "getUserCongressionalDistrict - no congressional district found in censusData -",
                    censusData,
                );
                return fail();
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
                fail();
            } else {
                resolve(created);
            }
        },
    });
