/** @format */

import {
    NOTIFY_COMPLETED_REGISTRATION,
    ROUTES,
    SWAY_USER_REGISTERED,
} from "@sway/constants";
import {
    getUserLocales,
    isEmptyObject,
    isNotUsersLocale,
    setStorage,
    toUserLocale,
} from "@sway/utils";
import { useEffect } from "react";
import { useHistory } from "react-router";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { handleError, notify, withTadas } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const Legislators: React.FC<ILocaleUserProps> = ({ user }) => {
    const history = useHistory();
    const search = history.location.search;
    const searchParams = new URLSearchParams(search);
    const queryStringCompletedRegistration = searchParams.get(
        NOTIFY_COMPLETED_REGISTRATION,
    );

    const [locale, setLocale] = useLocale(user);
    const [legislators, getRepresentatives, isLoadingLegislators] =
        useHookedRepresentatives();

    useEffect(() => {
        if (queryStringCompletedRegistration === "1") {
            if (localStorage.getItem(NOTIFY_COMPLETED_REGISTRATION)) {
                searchParams.delete(NOTIFY_COMPLETED_REGISTRATION);
                return;
            }
            localStorage.setItem(NOTIFY_COMPLETED_REGISTRATION, "1");
            notify({
                level: "success",
                title: withTadas("Welcome to Sway"),
                message: "Click/Tap here to start voting and earning sway!",
                tada: true,
                duration: 100000,
                onClick: () => history.push(ROUTES.billOfTheWeek),
            });
        }

        if (!locale) return;
        const _isActive = true;
        setStorage(SWAY_USER_REGISTERED, "1");

        getRepresentatives(user, toUserLocale(locale), _isActive).catch(
            handleError,
        );
    }, [user]);

    if (isLoadingLegislators) {
        return <FullWindowLoading message={"Loading Legislators..."} />;
    }
    if (!legislators) {
        return <FullWindowLoading message={"Finding Legislators..."} />;
    }
    if (!legislators && !user?.locales) {
        return (
            <div className={"legislators-list"}>
                <p className="no-legislators-message">
                    No Legislators. Are you logged in?
                </p>
            </div>
        );
    }
    if (isNotUsersLocale(user, locale)) {
        return <FullWindowLoading message={"Updating Legislators..."} />;
    }

    const { representatives, isActive } = legislators;

    const sorted = [...representatives].sort((a, b) =>
        a.district > b.district ? -1 : 1,
    );

    const render =
        !user || isEmptyObject(representatives) ? (
            <p className="no-legislators-message">No Legislators</p>
        ) : (
            sorted.map((legislator: sway.ILegislator, index: number) => (
                <LegislatorCard
                    key={index}
                    locale={locale}
                    user={user}
                    legislator={legislator}
                />
            ))
        );

    const handleSetLegislatorLocale = (
        newLocale: sway.IUserLocale | sway.ILocale,
    ) => {
        setLocale(newLocale);
        getRepresentatives(user, toUserLocale(newLocale), isActive).catch(
            handleError,
        );
    };

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={locale}
                    setLocale={handleSetLegislatorLocale}
                    locales={getUserLocales(user)}
                    containerStyle={{ width: "95%" }}
                />
            </div>
            <div className={"legislators-list"}>{render}</div>
            <SwayFab user={user} />
        </>
    );
};

export default Legislators;
