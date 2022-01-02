/** @format */

import Divider from "@mui/material/Divider";
import List from "@mui/material/List";
import { getUserLocales, isEmptyObject } from "@sway/utils";
import React, { useEffect, useState } from "react";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { useBills } from "../../hooks/bills";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import BillsListCategoriesHeader from "./BillsListCategoriesHeader";
import BillsListItem from "./BillsListItem";

const BillsList: React.FC<ILocaleUserProps> = ({ user }) => {
    const [locale, setLocale] = useLocale(user);
    const [bills, getBills, isLoading] = useBills();
    const [categories, setCategories] = useState<string[]>([]);

    const uid = user && user.isRegistrationComplete ? user.uid : null;

    useEffect(() => {
        getBills(locale, uid, categories);
    }, [locale, uid, categories, getBills]);

    if (isLoading || (isEmptyObject(bills) && isEmptyObject(categories))) {
        return (
            <FullWindowLoading message={"Loading Past Bills of the Week..."} />
        );
    }

    const handleSetCategories = (_categories: string[]) => {
        setCategories(_categories);
    };

    const render = () => {
        if (isEmptyObject(bills)) {
            return (
                <div style={{ margin: "20px auto", textAlign: "center" }}>
                    <p className="no-legislators-message">
                        {`No bills in categories - ${categories.join(", ")}`}
                    </p>
                </div>
            );
        }

        return bills // eslint-disable-next-line
            .filter((item) => !!item.bill.createdAt) // @ts-ignore
            .sort((a, b) => (a.bill.createdAt < b.bill.createdAt ? 1 : -1))
            .map((item: sway.IBillOrgsUserVote, index: number) => {
                if (index !== bills.length - 1) {
                    return (
                        <React.Fragment key={index}>
                            <BillsListItem
                                user={user}
                                locale={locale}
                                bill={item.bill}
                                organizations={item.organizations}
                                userVote={item.userVote}
                                index={index}
                            />
                            <Divider variant="inset" component="li" />
                        </React.Fragment>
                    );
                }
                return (
                    <BillsListItem
                        user={user}
                        key={index}
                        locale={locale}
                        bill={item.bill}
                        organizations={item.organizations}
                        userVote={item.userVote}
                        index={index}
                    />
                );
            })
            .filter(Boolean);
    };

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={locale}
                    locales={getUserLocales(user)}
                    setLocale={setLocale}
                    containerStyle={{ width: "95%" }}
                />
            </div>
            <BillsListCategoriesHeader
                categories={categories}
                setCategories={handleSetCategories}
            />
            <List>{render()}</List>
            <SwayFab user={user} />
        </>
    );
};
export default BillsList;
