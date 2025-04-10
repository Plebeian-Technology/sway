/** @format */

import SwayLoading from "app/frontend/components/SwayLoading";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useMemo, useState } from "react";
import { InView } from "react-intersection-observer";
import { sway } from "sway";
import BillsListCategoriesHeader from "../components/bill/BillsListCategoriesHeader";
import BillsListItem from "../components/bill/BillsListItem";
import LocaleSelector from "../components/user/LocaleSelector";

interface IProps {
    bills: sway.IBill[];
}

const Bills_: React.FC<IProps> = ({ bills }) => {
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

        return bills.map(
            (b, i) =>
                (!categories.length || categories.includes(b.category)) && (
                    <InView key={`bill-${locale.name}-${b.external_id}`} triggerOnce initialInView={i < 3}>
                        {({ inView, ref }) =>
                            !inView ? (
                                <div ref={ref} style={{ minHeight: "200px" }}>
                                    <SwayLoading />
                                </div>
                            ) : (
                                <div ref={ref} style={{ minHeight: "200px" }}>
                                    <BillsListItem
                                        bill={b}
                                        index={i}
                                        isLastItem={i === bills.length - 1}
                                        inView={inView}
                                    />
                                </div>
                            )
                        }
                    </InView>
                ),
        );
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
                <div className="col">{render}</div>
            </div>
        </div>
    );
};

const Bills = Bills_;
export default Bills;
