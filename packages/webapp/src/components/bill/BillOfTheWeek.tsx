/** @format */

import React, { useEffect, useState } from "react";
import { sway } from "sway";
import { isEmptyObject, IS_DEVELOPMENT, legisFire } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import Bill from "./Bill";

const BillOfTheWeek: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const [billOfTheWeek, setBillOfTheWeek] = useState<
        sway.IBillWithOrgs | undefined
    >();

    useEffect(() => {
        const load = async () => {
            if (!locale) return;

            const _bill: sway.IBill | void = await legisFire(locale)
                .bills()
                .latest();
            if (!_bill) return;

            const _organizations = await legisFire(locale)
                .organizations()
                .listPositions(_bill.firestoreId);

            setBillOfTheWeek({ bill: _bill, organizations: _organizations });
        };
        locale && load();
    }, [locale]);

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
            {!user?.uid && renderLocaleSelector()}
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
