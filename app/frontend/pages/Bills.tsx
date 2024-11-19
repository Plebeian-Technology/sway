/** @format */

import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useEffect, useMemo, useState } from "react";
import { Fade, ProgressBar } from "react-bootstrap";
import { InView } from "react-intersection-observer";
import { sway } from "sway";
import BillsListCategoriesHeader from "../components/bill/BillsListCategoriesHeader";
import BillsListItem from "../components/bill/BillsListItem";
import LocaleSelector from "../components/user/LocaleSelector";
import { router } from "@inertiajs/react";

interface IProps {
    bills: sway.IBill[];
}

const Bills_: React.FC<IProps> = ({ bills }) => {
    const [locale] = useLocale();
    const [categories, setCategories] = useState<string[]>([]);

    useEffect(() => {
        router.reload({ only: ["user_votes"] });
    }, []);

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
            <InView key={`bill-${locale.name}-${b.externalId}`} triggerOnce initialInView={i < 3}>
                {({ inView, ref }) =>
                    !inView ? (
                        <div ref={ref} style={{ minHeight: "200px" }}>
                            <ProgressBar animated striped now={100} />
                        </div>
                    ) : (
                        <div ref={ref} style={{ minHeight: "200px" }}>
                            <BillsListItem bill={b} index={i} isLastItem={i === bills.length - 1} inView={inView} />
                        </div>
                    )
                }
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
