/** @format */

import {
    BALTIMORE_CITY_LOCALE_NAME,
    CONGRESS_LOCALE,
    CONGRESS_LOCALE_NAME,
    LOCALES,
    NOTIFY_COMPLETED_REGISTRATION,
    ROUTES,
    SwayStorage,
} from "@sway/constants";
import { isEmptyObject, isNotUsersLocale, logDev, toUserLocale } from "@sway/utils";
import { useEffect } from "react";
import { Button } from "react-bootstrap";
import { useLocation, useNavigate } from "react-router";
import { sway } from "sway";
import { useFirebaseUser, useLocale, useUser } from "../../hooks";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { handleError, localGet, localSet, notify, withTadas } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import LocaleAvatar from "../locales/LocaleAvatar";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const BALTIMORE_CITY_USER_LOCALE = {
    ...toUserLocale(BALTIMORE_CITY_LOCALE_NAME),
    district: "MD0",
};

const Legislators: React.FC<ILocaleUserProps> = () => {
    const navigate = useNavigate();
    const search = useLocation().search;
    const user = useUser();
    const [firebaseUser] = useFirebaseUser();
    const searchParams = new URLSearchParams(search);
    const queryStringCompletedRegistration = searchParams.get(NOTIFY_COMPLETED_REGISTRATION);
    const [locale, setLocale] = useLocale(user);
    const { sendEmailVerification } = useEmailVerification();

    const [legislators, getRepresentatives, isLoadingLegislators] = useHookedRepresentatives();

    useEffect(() => {
        if (queryStringCompletedRegistration === "1") {
            if (localGet(NOTIFY_COMPLETED_REGISTRATION)) {
                searchParams.delete(NOTIFY_COMPLETED_REGISTRATION);
            } else {
                localSet(NOTIFY_COMPLETED_REGISTRATION, "1");
                notify({
                    level: "success",
                    title: withTadas("Welcome to Sway"),
                    message: "Click/tap here to start voting and earning Sway!",
                    tada: true,
                    duration: 200000,
                    onClick: () => navigate(ROUTES.billOfTheWeek),
                });
            }
        }

        const _isActive = true;
        localSet(SwayStorage.Local.User.Registered, "1");

        logDev("Legislators.useEffect - getRepresentatives");
        getRepresentatives(
            user,
            user && user.locales
                ? user.locales.find((l) => l.name === locale.name) || (locale as sway.IUserLocale)
                : (locale as sway.IUserLocale),
            _isActive,
        ).catch(handleError);
    }, [user?.locales, locale.name]);

    if (isLoadingLegislators) {
        return <FullWindowLoading message={"Loading Legislators..."} />;
    }
    if (!legislators) {
        return (
            <div className="container text-center">
                <LocaleSelector
                    locale={locale}
                    setLocale={setLocale}
                    locales={user.locales || LOCALES}
                />
                <p className="no-legislators-message pt-5">
                    No legislators found. Are you logged in?
                </p>
            </div>
        );
    }
    // if (isNotUsersLocale(user, BALTIMORE_CITY_USER_LOCALE) && !isNotUsersLocale(user, CONGRESS_LOCALE)) {
    //     return <FullWindowLoading message={"Updating Legislators..."} />;
    // }

    const { representatives } = legislators;

    const sorted = [...representatives].sort((a, b) => (a.district > b.district ? -1 : 1));

    const render =
        !user || isEmptyObject(representatives) ? (
            <p>No Legislators</p>
        ) : (
            sorted.map((legislator: sway.ILegislator, index: number) => (
                <div key={legislator.externalId} className={index > 0 ? "row my-3" : "row"}>
                    <LegislatorCard
                        locale={BALTIMORE_CITY_USER_LOCALE}
                        user={user}
                        legislator={legislator}
                    />
                    {index === sorted.length - 1 ? null : (
                        <div className="col-12 text-center">
                            <LocaleAvatar locale={locale} />
                        </div>
                    )}
                </div>
            ))
        );

    const handleResendActivationEmail = () => {
        if (!firebaseUser) return;

        sendEmailVerification(firebaseUser).catch(handleError);
    };

    return (
        <div className="row">
            <div className="col">
                {!user.isEmailVerified && (
                    <div className="row my-3 w-100">
                        <div className="col text-center">
                            <Button variant="info" onClick={handleResendActivationEmail}>
                                Verify email to start voting!
                            </Button>
                        </div>
                    </div>
                )}
                <div className="row">
                    <div className="col">
                        <LocaleSelector locale={locale} setLocale={setLocale} />
                    </div>
                </div>
                <div className="row">
                    <div className="col">{render}</div>
                </div>
            </div>
        </div>
    );
};

export default Legislators;
