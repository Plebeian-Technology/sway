/** @format */

import {
    findLocale,
    getUserLocales,
    isEmptyObject,
    isNotUsersLocale,
    IS_DEVELOPMENT,
} from "@sway/utils";
import React, { useEffect } from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { useBillOfTheWeek } from "../../hooks/bills";
import { signInAnonymously } from "../../users/signinAnonymously";
import { handleError, notify } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import Bill from "./Bill";

const BillOfTheWeek: React.FC<ILocaleUserProps> = ({ user }) => {
    const history = useHistory();
    const search = history.location.search;
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
                signInAnonymously()
                    .then(() => getBillOfTheWeek(locale, uid))
                    .catch(handleError);
            } else {
                getBillOfTheWeek(locale, uid);
            }
        };
        load().catch(handleError);
    }, [locale, uid, getBillOfTheWeek]);

    useEffect(() => {
        const timeout = setTimeout(() => {
            if (!billOfTheWeek) {
                notify({
                    level: "error",
                    title: "Error getting bill. Navigating home",
                    message: "Please try logging in again.",
                });
                setTimeout(() => {
                    window.location.href = "/";
                }, 2000);
            }
        }, 7000);
        return () => clearTimeout(timeout);
    }, [billOfTheWeek]);

    const isLoading = () => {
        if (isLoadingBill) return true;
        if (!locale.name) {
            IS_DEVELOPMENT && console.log("BILL OF THE WEEK - NO LOCALE (dev)");
            return true;
        }
        if (!billOfTheWeek || isEmptyObject(billOfTheWeek)) {
            IS_DEVELOPMENT && console.log("BILL OF THE WEEK - EMPTY (dev)");
            return true;
        }
        if (locale && user && user.isAnonymous) {
            IS_DEVELOPMENT &&
                console.log("BILL OF THE WEEK - ANONYMOUS USER (dev)");
            return false;
        }
        if (user?.uid && !user.locales) {
            IS_DEVELOPMENT &&
                console.log("BILL OF THE WEEK - USER NO LOCALE (dev)");
            return true;
        }
        if (isNotUsersLocale(user, locale)) {
            IS_DEVELOPMENT &&
                console.log("BILL OF THE WEEK - LOCALE MISMATCH (dev)");
            return true;
        }
        return false;
    };

    if (isLoading()) {
        // return <CenteredLoading message={"Loading Bill of the Week..."} />;
        return <FullWindowLoading message={"Loading Bill of the Week..."} />;
    }

    const handleSetBillLocale = (newLocale: sway.ILocale) => {
        setLocale(newLocale);
        getBillOfTheWeek(newLocale, uid);
    };

    // Handled in isLoading but Typescript doesn't recognize that
    if (!billOfTheWeek) return null;

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={locale}
                    locales={getUserLocales(user)}
                    setLocale={handleSetBillLocale}
                    containerStyle={{ width: "95%" }}
                />
            </div>
            <Bill
                bill={billOfTheWeek.bill}
                organizations={billOfTheWeek.organizations}
                userVote={billOfTheWeek.userVote}
                locale={locale}
                user={user}
            />
            <SwayFab user={user} />
        </>
    );
};

export default BillOfTheWeek;
