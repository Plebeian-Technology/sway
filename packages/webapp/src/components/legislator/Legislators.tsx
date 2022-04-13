/** @format */

import {
    BALTIMORE_CITY_LOCALE_NAME,
    NOTIFY_COMPLETED_REGISTRATION,
    ROUTES,
    SWAY_USER_REGISTERED,
} from "@sway/constants";
import { isEmptyObject, isNotUsersLocale, logDev, setStorage, toUserLocale } from "@sway/utils";
import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router";
import { sway } from "sway";
import { useUser } from "../../hooks";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { handleError, notify, withTadas } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const BALTIMORE_CITY_USER_LOCALE = {
    ...toUserLocale(BALTIMORE_CITY_LOCALE_NAME),
    district: "MD0",
};

const Legislators: React.FC<ILocaleUserProps> = () => {
    const navigate = useNavigate();
    const user = useUser();
    const search = useLocation().search;
    const searchParams = new URLSearchParams(search);
    const queryStringCompletedRegistration = searchParams.get(NOTIFY_COMPLETED_REGISTRATION);

    const [legislators, getRepresentatives, isLoadingLegislators] = useHookedRepresentatives();

    useEffect(() => {
        if (queryStringCompletedRegistration === "1") {
            if (localStorage.getItem(NOTIFY_COMPLETED_REGISTRATION)) {
                searchParams.delete(NOTIFY_COMPLETED_REGISTRATION);
            } else {
                localStorage.setItem(NOTIFY_COMPLETED_REGISTRATION, "1");
                notify({
                    level: "success",
                    title: withTadas("Welcome to Sway"),
                    message:
                        "Click/Tap 'Find Legislators' in the menu to find your district-specific representatives or click/tap here to start voting and earning sway!",
                    tada: true,
                    duration: 200000,
                    onClick: () => navigate(ROUTES.billOfTheWeek),
                });
            }
        }

        const _isActive = true;
        setStorage(SWAY_USER_REGISTERED, "1");

        logDev("Legislators.useEffect - getRepresentatives");
        getRepresentatives(
            user,
            user && user.locales ? user.locales[0] : BALTIMORE_CITY_USER_LOCALE,
            _isActive,
        ).catch(handleError);
    }, [user?.locales]);

    if (isLoadingLegislators) {
        return <FullWindowLoading message={"Loading Legislators..."} />;
    }
    if (!legislators) {
        return <FullWindowLoading message={"Finding Legislators..."} />;
    }
    if (!legislators && !user?.locales) {
        return (
            <div className={"legislators-list"}>
                <p className="no-legislators-message">No Legislators. Are you logged in?</p>
            </div>
        );
    }
    if (isNotUsersLocale(user, BALTIMORE_CITY_USER_LOCALE)) {
        return <FullWindowLoading message={"Updating Legislators..."} />;
    }

    const { representatives } = legislators;

    const sorted = [...representatives].sort((a, b) => (a.district > b.district ? -1 : 1));

    const render =
        !user || isEmptyObject(representatives) ? (
            <p className="no-legislators-message">No Legislators</p>
        ) : (
            sorted.map((legislator: sway.ILegislator, index: number) => (
                <div key={legislator.externalId} className={index > 0 ? "row my-3" : "row"}>
                    <LegislatorCard
                        key={index}
                        locale={BALTIMORE_CITY_USER_LOCALE}
                        user={user}
                        legislator={legislator}
                    />
                </div>
            ))
        );

    return (
        <div className="row">
            <div className="col">{render}</div>
            <SwayFab user={user} />
        </div>
    );
};

export default Legislators;
