/** @format */

import { ESwayLevel } from "@sway/constants";
import React, { useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { signInAnonymously } from "../../users/signinAnonymously";
import {
    handleError,
    isEmptyObject,
    IS_DEVELOPMENT,
    legisFire
} from "../../utils";
import { congressLocale } from "../../utils/locales";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import Bill from "./Bill";
import BillLevelHeader from "./BillLevelHeader";

const BillOfTheWeek: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const [level, setLevel] = useState<ESwayLevel>(ESwayLevel.Local);
    const [billOfTheWeek, setBillOfTheWeek] = useState<
        sway.IBillWithOrgs | undefined
    >();

    const loadBillAndOrgs = useCallback((_level: ESwayLevel) => {
        const selectLocale = () => {
            if (_level === ESwayLevel.Local) return locale;
            return congressLocale(locale._region);
        }
        legisFire(selectLocale())
            .bills()
            .latest()
            .then((_bill) => {
                if (!_bill) return;

                legisFire(locale)
                    .organizations()
                    .listPositions(_bill.firestoreId)
                    .then((_organizations) => {
                        setBillOfTheWeek({
                            bill: _bill,
                            organizations: _organizations,
                        });
                    })
                    .catch(handleError);
            })
            .catch(handleError);
    }, []);

    useEffect(() => {
        const load = async () => {
            if (!locale) return;
            if (!user) {
                signInAnonymously().then(() => loadBillAndOrgs(level)).catch(handleError);
            } else {
                loadBillAndOrgs(level);
            }
        };
        locale && load();
    }, [locale, level]);

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

    const renderLocaleSelector = () => {
        return (
            <div className={"bill-of-the-week-locale-selector-container"}>
                <LocaleSelector containerStyle={{ width: "90%" }} />
            </div>
        );
    };

    const { bill, organizations } = billOfTheWeek as sway.IBillWithOrgs;
    return (
        <>
            {(!user?.uid || user.isAnonymous) && renderLocaleSelector()}
            <BillLevelHeader level={level} setLevel={setLevel} user={user} />
            <Bill
                bill={bill}
                organizations={organizations}
                locale={locale}
                user={user}
            />
            <SwayFab user={user} />
        </>
    );
};

export default BillOfTheWeek;
