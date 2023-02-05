/** @format */

import { isEmptyObject } from "@sway/utils";
import React, { useEffect, useMemo, useState } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import { useBills } from "../../hooks/bills";
import { handleError } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";
import LocaleSelector from "../user/LocaleSelector";
import BillsListCategoriesHeader from "./BillsListCategoriesHeader";
import BillsListItem from "./BillsListItem";

const BillsList: React.FC = () => {
    const [bills, getBills, isLoading] = useBills();
    const [categories, setCategories] = useState<string[]>([]);

    useEffect(() => {
        getBills(categories).catch(handleError);
    }, [categories, getBills]);

    const render = useMemo(() => {
        if (isEmptyObject(bills) && isEmptyObject(categories)) {
            return <CenteredLoading className="mt-2" message="Loading Past Bills of the Week..." />;
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

        const sorted = [...bills].sort((a, b) =>
            a?.bill?.createdAt && b?.bill?.createdAt && a?.bill?.createdAt < b?.bill?.createdAt
                ? 1
                : -1,
        );

        const toRender = [];
        let i = 0;
        while (i < bills.length) {
            const item = sorted[i] as sway.IBillOrgsUserVote;
            if (item?.bill?.createdAt) {
                toRender.push(
                    <BillsListItem
                        key={i}
                        bill={item.bill}
                        organizations={item.organizations}
                        userVote={item.userVote}
                        index={i}
                        isLastItem={i === sorted.length - 1}
                    />,
                );
            }
            i++;
        }

        return toRender;
    }, [bills, categories]);

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <LocaleSelector />
                </div>
            </div>

            <div className="row">
                <div className="col">
                    <BillsListCategoriesHeader
                        categories={categories}
                        setCategories={setCategories}
                    />
                </div>
            </div>
            <div className="row border-top mt-5">
                <Animate play={!isLoading} start={{ opacity: 0 }} end={{ opacity: 1 }}>
                    <div className="col">{render}</div>
                </Animate>
            </div>
        </div>
    );
};
export default BillsList;
