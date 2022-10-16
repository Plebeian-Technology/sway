/** @format */

import { SwayStorage } from "@sway/constants";
import { findLocale, getUserLocales, isEmptyObject, isNotUsersLocale, logDev } from "@sway/utils";
import React, { useEffect } from "react";
import { useLocation } from "react-router-dom";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { useBillOfTheWeek } from "../../hooks/bills";
import { useCancellable } from "../../hooks/cancellable";
import { anonymousSignIn } from "../../users/signinAnonymously";
import { handleError, localSet, notify } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import Bill from "./Bill";

const BillOfTheWeek: React.FC<ILocaleUserProps> = ({ user }) => {
    const makeCancellable = useCancellable();
    const search = useLocation().search;
    const queryStringLocaleName = new URLSearchParams(search).get("locale");

    const [locale, setLocale] = useLocale(
        user,
        queryStringLocaleName ? findLocale(queryStringLocaleName) : null,
    );
    const [billOfTheWeek, getBillOfTheWeek, isLoadingBill] = useBillOfTheWeek();

    const uid = user && user.isRegistrationComplete ? user.uid : null;

    useEffect(() => {
        const load = async () => {
            if (!user) {
                logDev("Load BOTW as ANON user.");
                anonymousSignIn()
                    .then(() => getBillOfTheWeek(locale, uid))
                    .catch(handleError);
            } else {
                logDev("Load BOTW as AUTHED user.");
                localSet(SwayStorage.Local.User.Registered, "1");
                getBillOfTheWeek(locale, uid);
            }
        };
        makeCancellable(load(), () => logDev("Cancelled BillOfTheWeek.load")).catch(handleError);
    }, [locale, uid, getBillOfTheWeek]);

    useEffect(() => {
        const timeout = setTimeout(() => {
            if (!billOfTheWeek) {
                notify({
                    level: "error",
                    title: "Error getting bill of the week.",
                    message: "Please try logging in again.",
                });
                setTimeout(() => {
                    window.location.href = "/";
                }, 2000);
            }
        }, 10000);
        return () => clearTimeout(timeout);
    }, [billOfTheWeek]);

    const isLoading = () => {
        if (isLoadingBill) return true;
        if (!locale.name) {
            logDev("BILL OF THE WEEK - NO LOCALE");
            return true;
        }
        if (!billOfTheWeek || isEmptyObject(billOfTheWeek)) {
            logDev("BILL OF THE WEEK - EMPTY");
            return true;
        }
        if (locale && user && user.isAnonymous) {
            logDev("BILL OF THE WEEK - ANONYMOUS USER");
            return false;
        }
        if (user?.uid && !user.locales) {
            logDev("BILL OF THE WEEK - USER NO LOCALE");
            return true;
        }
        if (isNotUsersLocale(user, locale)) {
            logDev("BILL OF THE WEEK - LOCALE MISMATCH");
            return true;
        }
        return false;
    };

    const handleSetBillLocale = (newLocale: sway.ILocale) => {
        setLocale(newLocale);
        getBillOfTheWeek(newLocale, uid);
    };

    if (isLoading()) {
        return <FullWindowLoading message="Loading Bill of the Week..." />;
    }

    // Handled in isLoading but Typescript doesn't recognize that
    if (!billOfTheWeek) return null;

    logDev("BillOfTheWeek.bill -", { billOfTheWeek, locale });

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <LocaleSelector
                        locale={locale}
                        locales={getUserLocales(user)}
                        setLocale={handleSetBillLocale}
                    />
                </div>
            </div>
            <div className="row">
                <div className="col">
                    <Bill
                        bill={billOfTheWeek.bill}
                        organizations={billOfTheWeek.organizations}
                        userVote={billOfTheWeek.userVote}
                        locale={locale}
                        user={user}
                    />
                </div>
            </div>
        </div>
    );
};

export default BillOfTheWeek;
