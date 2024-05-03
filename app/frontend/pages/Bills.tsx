/** @format */

import { isEmptyObject } from "app/frontend/sway_utils";
import { useMemo, useState } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import BillsListCategoriesHeader from "../components/bill/BillsListCategoriesHeader";
import BillsListItem from "../components/bill/BillsListItem";
import LocaleSelector from "../components/user/LocaleSelector";

const Bills: React.FC<{ bills: sway.IBill[] }> = ({ bills }) => {
    const [categories, setCategories] = useState<string[]>([]);

    const render = useMemo(() => {
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
            a?.createdAt && b?.createdAt && a?.createdAt < b?.createdAt
                ? 1
                : -1,
        );

        const toRender = [];
        let i = 0;
        while (i < bills.length) {
            const item = sorted[i] as sway.IBill;
            if (item?.createdAt) {
                toRender.push(
                    <BillsListItem
                        key={i}
                        bill={item}
                        // organizations={item.organizations}
                        // userVote={item.userVote}
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
                <Animate play={true} start={{ opacity: 0 }} end={{ opacity: 1 }}>
                    <div className="col">{render}</div>
                </Animate>
            </div>
        </div>
    );
};
export default Bills;
