/** @format */

import {
    getUserLocales, isEmptyObject,
    isNotUsersLocale,

    IS_DEVELOPMENT
} from "@sway/utils";
import React, { useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { signInAnonymously } from "../../users/signinAnonymously";
import {
    handleError,
    legisFire
} from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import Bill from "./Bill";

const BillOfTheWeek: React.FC<ILocaleUserProps> = ({ user }) => {
    const [locale, setLocale] = useLocale(user);
    const [billOfTheWeek, setBillOfTheWeek] = useState<
        sway.IBillWithOrgs | undefined
    >();
    const [isLoadingBill, setIsLoadingBill] = useState<boolean>(false);

    const loadBillAndOrgs = useCallback((_locale: sway.ILocale) => {
        const setBotwWithOrganizations = (bill: sway.IBill | void) => {
            if (!bill) return;

            legisFire(_locale)
                .organizations()
                .listPositions(bill.firestoreId)
                .then((_organizations) => {
                    setBillOfTheWeek({
                        bill,
                        organizations: _organizations,
                    });
                })
                .catch(handleError);
        };
        setIsLoadingBill(true);
        legisFire(_locale)
            .bills()
            .latestCreatedAt()
            .then(setBotwWithOrganizations)
            .catch(handleError).finally(() => setIsLoadingBill(false));
    }, [setIsLoadingBill]);

    useEffect(() => {
        const load = async () => {
            if (!user) {
                signInAnonymously()
                    .then(() => loadBillAndOrgs(locale))
                    .catch(handleError);
            } else {
                loadBillAndOrgs(locale);
            }
        };
        load().catch(handleError);
    }, [locale, loadBillAndOrgs]);

    const isLoading = () => {
        if (isLoadingBill) return true;
        if (!locale.name) {
            IS_DEVELOPMENT && console.log("BILL OF THE WEEK - NO LOCALE (dev)");
            return true;
        }
        if (isEmptyObject(billOfTheWeek)) {
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
        loadBillAndOrgs(newLocale);
    }

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={locale}
                    locales={getUserLocales(user)}
                    setLocale={handleSetBillLocale}
                    containerStyle={{ width: "90%" }}
                />
            </div>
            <Bill
                bill={(billOfTheWeek as sway.IBillWithOrgs).bill}
                organizations={
                    (billOfTheWeek as sway.IBillWithOrgs).organizations
                }
                locale={locale}
                user={user}
            />
            <SwayFab user={user} />
        </>
    );
};

export default BillOfTheWeek;
