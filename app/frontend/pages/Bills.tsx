/** @format */

import SetupPage from "app/frontend/components/hoc/SetupPage";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useMemo, useState } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import BillsListCategoriesHeader from "../components/bill/BillsListCategoriesHeader";
import BillsListItem from "../components/bill/BillsListItem";
import LocaleSelector from "../components/user/LocaleSelector";

const _Bills: React.FC<{ bills: sway.IBill[] }> = ({ bills }) => {
    const [locale] = useLocale();
    const [categories, setCategories] = useState<string[]>([]);

    const render = useMemo(() => {
        if (!bills.length) {
            return (
                <div className="my-4 text-center">
                    <p className="no-legislators-message">
                        {isEmpty(categories)
                            ? `No bills found for ${toFormattedLocaleName(locale.name)}`
                            : `No bills in categories - ${categories.join(", ")}`}
                    </p>
                </div>
            );
        }

        return bills.map((b, i) => (
            <BillsListItem
                key={i}
                bill={b}
                index={i}
                isLastItem={i === bills.length - 1}
            />
        ));
    }, [bills, categories, locale.name]);

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <LocaleSelector />
                </div>
            </div>

            <div className="row">
                <div className="col">
                    <BillsListCategoriesHeader categories={categories} setCategories={setCategories} />
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
const Bills = SetupPage(_Bills);
export default Bills;
