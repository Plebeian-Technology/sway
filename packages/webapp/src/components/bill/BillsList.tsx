/** @format */

import Divider from "@mui/material/Divider";
import List from "@mui/material/List";
import { getUserLocales, isEmptyObject } from "@sway/utils";
import React, { useEffect, useState } from "react";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { useBills } from "../../hooks/bills";
import CenteredLoading from "../dialogs/CenteredLoading";
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

    const handleSetCategories = (_categories: string[]) => {
        setCategories(_categories);
    };

    const render = () => {
        if (isLoading || (isEmptyObject(bills) && isEmptyObject(categories))) {
            return (
                <CenteredLoading
                    message={"Loading Past Bills of the Week..."}
                />
            );
        }

        if (isEmptyObject(bills)) {
            return (
                <div className="my-4 text-center">
                    <p className="no-legislators-message">
                        {`No bills in categories - ${categories.join(", ")}`}
                    </p>
                </div>
            );
        }

        const sorted = bills.sort((a, b) =>
            a?.bill?.createdAt &&
            b?.bill?.createdAt &&
            a?.bill?.createdAt < b?.bill?.createdAt
                ? 1
                : -1,
        );
        const toRender = [];
        let i = 0;
        while (i < bills.length) {
            const item = sorted[i] as sway.IBillOrgsUserVote;
            if (!item?.bill?.createdAt) {
                // noop
            } else {
                toRender.push(
                    <BillsListItem
                        key={i}
                        user={user}
                        locale={locale}
                        bill={item.bill}
                        organizations={item.organizations}
                        userVote={item.userVote}
                        index={i}
                    />,
                );
                if (i !== sorted.length - 1) {
                    toRender.push(
                        <Divider
                            key={`${i}-divider`}
                            variant="inset"
                            component="li"
                        />,
                    );
                }
            }
            i++;
        }

        return toRender;
    };

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <LocaleSelector
                        locale={locale}
                        locales={getUserLocales(user)}
                        setLocale={setLocale}
                    />
                </div>
            </div>

            <div className="row">
                <div className="col">
                    <BillsListCategoriesHeader
                        categories={categories}
                        setCategories={handleSetCategories}
                    />
                </div>
            </div>
            <div className="row">
                <div className="col">
                    <List>{render()}</List>
                </div>
            </div>
            <SwayFab user={user} />
        </div>
    );
};
export default BillsList;
