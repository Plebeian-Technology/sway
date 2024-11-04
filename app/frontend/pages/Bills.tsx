/** @format */

import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useMemo, useState } from "react";
import { Fade } from "react-bootstrap";
import { sway } from "sway";
import BillsListCategoriesHeader from "../components/bill/BillsListCategoriesHeader";
import BillsListItem from "../components/bill/BillsListItem";
import LocaleSelector from "../components/user/LocaleSelector";
import { InView } from "react-intersection-observer";

const Bills_: React.FC<{ bills: sway.IBill[] }> = ({ bills }) => {
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
            <InView key={`bill-${locale.name}-${b.externalId}`} triggerOnce initialInView={i < 5}>
                {({ inView, ref }) => (
                    <div ref={ref} style={{ minHeight: "100px" }}>
                        <BillsListItem bill={b} index={i} isLastItem={i === bills.length - 1} inView={inView} />
                    </div>
                )}
            </InView>
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
                <Fade in={true}>
                    <div className="col">{render}</div>
                </Fade>
            </div>
        </div>
    );
};

const Bills = Bills_;
export default Bills;
