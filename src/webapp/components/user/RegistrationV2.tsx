/** @format */

import {
    BALTIMORE_CITY_LOCALE_NAME,
    COUNTRY_NAMES,
    NOTIFY_COMPLETED_REGISTRATION,
    SWAY_REDEEMING_INVITE_FROM_UID_COOKIE,
    SWAY_USER_REGISTERED,
} from "src/constants";
import {
    getStorage,
    isEmptyObject,
    logDev,
    removeStorage,
    setStorage,
    titleize,
    toLocale,
} from "src/utils";
import React, { useEffect } from "react";
import { sway } from "sway";
import { useInviteUid, useUser } from "../../hooks";
import { handleError, swayFireClient } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";

export const ADDRESS_FIELDS = ["address1", "address2", "postalCode"];

export interface IValidateResponseData {
    address1: string;
    address2: string;
    region: string;
    city: string;
    postalCode: string;
    postalCodeExtension: string;
}

const Registration: React.FC = () => {
    const invitedByUid = useInviteUid();
    const user: sway.IUser | undefined = useUser();

    const defaultUserLocales = () => {
        if (isEmptyObject(user.locales)) {
            const locale = toLocale(BALTIMORE_CITY_LOCALE_NAME);
            return [
                {
                    ...locale,
                    district: `${locale.regionCode.toUpperCase()}0`,
                },
            ] as sway.IUserLocale[];
        }
        return user.locales;
    };

    useEffect(() => {
        if (!user?.uid || user.isRegistrationComplete) {
            logDev(
                "Registration - no user uid or user.isRegistrationComplete is TRUE. Skipping registration. User -",
                user,
            );
            return;
        }

        const load = async () => {
            const locale = toLocale(BALTIMORE_CITY_LOCALE_NAME);
            const fireClient = swayFireClient(locale);

            const initial: sway.IUser = {
                createdAt: user.createdAt, // set in fire_users
                updatedAt: user.updatedAt, // set in fire_users
                email: user.email || "", // from firebase
                uid: user.uid || "", // from firebase
                locales: defaultUserLocales(),
                name: user.name || "",
                city: user.city ? titleize(user.city) : locale.city,
                region: user.region ? titleize(user.region) : locale.region,
                regionCode: user.regionCode || locale.regionCode.toUpperCase(),
                country: titleize(user.country) || COUNTRY_NAMES[0],
                creationTime: user.creationTime || "",
                lastSignInTime: user.lastSignInTime || "",
                isSwayConfirmed: false,
                isRegisteredToVote: true,
                isRegistrationComplete: true,
                // isRegistrationComplete: user.isRegistrationComplete || false,
                // isEmailVerified: user.isEmailVerified || false,
                isEmailVerified: true,
            } as sway.IUser;

            const values = {
                ...initial,
                invitedBy: isEmptyObject(invitedByUid)
                    ? getStorage(SWAY_REDEEMING_INVITE_FROM_UID_COOKIE)
                    : invitedByUid,
                country: locale.country.toLowerCase(),
                city: locale.city.toLowerCase(),
                region: locale.region.toLowerCase(),
                regionCode: locale.regionCode.toUpperCase(),
            } as sway.IUser;

            // NOTE: Also creates user settings from DEFAULT_USER_SETTINGS
            const isUpdating = Boolean(
                user && user.uid && user.isRegistrationComplete === false,
            );

            logDev("Registration - creating user from values -", values);
            const created = await fireClient
                .users(values.uid)
                .create(values, isUpdating);

            logDev("Creating user invites object.");
            await fireClient
                .userInvites(values.uid)
                .upsert({})
                .catch(handleError);

            if (created) {
                setStorage(SWAY_USER_REGISTERED, "1");
                removeStorage(SWAY_REDEEMING_INVITE_FROM_UID_COOKIE);
                if (user.isEmailVerified || created.isEmailVerified) {
                    localStorage.removeItem(NOTIFY_COMPLETED_REGISTRATION);
                    window.location.href = `/legislators?${NOTIFY_COMPLETED_REGISTRATION}=1`;
                } else {
                    window.location.href = "/?needsEmailActivation=1";
                }
            } else {
                handleError(
                    new Error("Error registering user."),
                    "Failed to register with Sway. Invalid information.",
                );
            }
        };

        load().catch(handleError);
    }, [user]);

    return (
        <div className={"registration-container"}>
            <CenteredLoading message={"Creating your profile..."} />
        </div>
    );
};

export default Registration;
