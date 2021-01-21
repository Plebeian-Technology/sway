/** @format */

import {
    CONGRESS_LOCALE_NAME,

    LOCALES
} from "@sway/constants";
import React, { useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { signInAnonymously } from "../../users/signinAnonymously";
import {
    handleError,
    isEmptyObject,
    IS_DEVELOPMENT,
    legisFire
} from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import Bill from "./Bill";

const BillOfTheWeek: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const [billLocale, setBillLocale] = useState(locale);
    const [billOfTheWeek, setBillOfTheWeek] = useState<
        sway.IBillWithOrgs | undefined
    >();

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
        legisFire(_locale)
            .bills()
            .latestCreatedAt()
            .then(setBotwWithOrganizations)
            .catch(handleError);
    }, []);

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
        if (user?.uid && !user.locale) {
            IS_DEVELOPMENT &&
                console.log("BILL OF THE WEEK - USER NO LOCALE (dev)");
            return true;
        }
        if (user?.locale?.name && user.locale.name !== locale.name) {
            IS_DEVELOPMENT &&
                console.log("BILL OF THE WEEK - LOCALE MISMATCH (dev)");
            return true;
        }
        return false;
    };

    if (isLoading()) {
        return <FullWindowLoading message={"Loading Bill of the Week..."} />;
    }

    const getLocales = () => {
        if (!user || !user?.locale?.name) {
            return LOCALES;
        }
        return LOCALES.filter(
            (l) =>
                l.name === user?.locale?.name ||
                l.name === CONGRESS_LOCALE_NAME,
        );
    };

    const handleSetBillLocale = (newLocale: sway.ILocale) => {
        setBillLocale(newLocale);
        loadBillAndOrgs(newLocale);
    }

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={billLocale}
                    locales={getLocales()}
                    setLocale={handleSetBillLocale}
                    containerStyle={{ width: "90%" }}
                />
            </div>
            <Bill
                bill={(billOfTheWeek as sway.IBillWithOrgs).bill}
                organizations={
                    (billOfTheWeek as sway.IBillWithOrgs).organizations
                }
                locale={billLocale}
                user={user}
            />
            <SwayFab user={user} />
        </>
    );
};

export default BillOfTheWeek;
