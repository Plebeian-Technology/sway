/** @format */

import { useLocale } from "app/frontend/hooks/useLocales";
import { isEmptyObject, titleize } from "app/frontend/sway_utils";
import { useCallback, useMemo, useRef, useState } from "react";
import { FiBarChart, FiBarChart2, FiFlag, FiMap } from "react-icons/fi";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { useIsCongressUserLocale } from "../../../hooks/locales/useUserLocale";
import { swayBlue } from "../../../sway_utils";
import { isEmptyScore } from "../../../sway_utils/charts";
import DialogWrapper from "../../dialogs/DialogWrapper";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";
import {
    collectDistrictScoresForState,
    setUserLocaleDistrictAsState,
    updateBillScoreWithUserVote,
} from "./bill_chart_utils";
import { BillChartFilters } from "./constants";

interface IProps {
    bill: sway.IBill;
    userVote?: sway.IUserVote;
    filter?: string;
}

export interface IChildChartProps {
    score: sway.IBillScore;
    billFirestoreId: string;
    selected?: true;
    handleClick: (index: number) => void;
    locale: sway.ISwayLocale;
    isEmptyScore: boolean;
}

interface IChartChoice {
    key: string;
    label: string;
    Icon: React.FC<any>;
    Component: React.FC<IChildChartProps>;
}

const BillMobileChartsContainer: React.FC<IProps> = ({ bill, userVote, filter }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [locale] = useLocale();
    const isCongressUserLocale = useIsCongressUserLocale();

    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(0);
    const [expanded, setExpanded] = useState<boolean>(false);

    const handleSetExpanded = useCallback(() => {
        setOpen(true);
        setExpanded(true);
    }, [setOpen]);

    const handleClose = useCallback(() => {
        setOpen(false);
        setExpanded(false);
    }, [setOpen]);

    const districtChartLabel = ""
    // const districtChartLabel = useMemo(() => {
    //     if (!locale?.district) return "";

    //     const textDistrict = getTextDistrict(locale.district);
    //     if (textDistrict) {
    //         return `${STATE_CODES_NAMES[textDistrict]} Total`;
    //     } else {
    //         return "Region Total";
    //     }
    // }, [locale?.district]);

    const components = useMemo(
        () => [
            {
                key: BillChartFilters.district,
                Component: DistrictVotesChart,
                Icon: FiMap,
                label: "District Total",
            },
            isCongressUserLocale
                ? {
                      key: BillChartFilters.state,
                      Component: DistrictVotesChart,
                      Icon: FiBarChart,
                      label: districtChartLabel,
                  }
                : null,
            {
                key: BillChartFilters.total,
                Component: TotalVotes,
                Icon: isCongressUserLocale ? FiFlag : FiBarChart2,
                label: isCongressUserLocale
                    ? "Congress Total"
                    : `${titleize(locale?.city || "")} Total`,
            },
        ],
        [locale?.city, isCongressUserLocale, districtChartLabel],
    );

    const charts = useMemo(() => {
        const _charts = [];
        for (const component of components) {
            if (component) {
                if (filter) {
                    if (component?.key === filter) {
                        _charts.push(component);
                    } else {
                        // no-op, component key !== filter
                    }
                } else {
                    _charts.push(component);
                }
            }
        }
        return _charts;
    }, [components, filter]);

    const selectedChart = useMemo(
        () => expanded && components[selected],
        [components, expanded, selected],
    );

    if (!userVote || !locale) return null;
    if (isEmptyObject(bill.score)) return null;

    return (
        <div ref={ref} className="col">
            <div className="row mb-2">
                {/* @ts-ignore */}
                {charts.map((item: IChartChoice, index: number) => {
                    const isSelected = index === selected;
                    return (
                        <div
                            key={index}
                            onClick={() => setSelected(index)}
                            className={`col text-center border border-2 rounded py-2 mx-2 ${
                                isSelected ? "border-primary blue" : ""
                            }`}
                        >
                            <div>{item.label}</div>
                            <div>
                                <item.Icon
                                    style={{
                                        color: index === selected ? swayBlue : "initial",
                                    }}
                                />
                            </div>
                        </div>
                    );
                })}
            </div>
            <div className="row">
                {/* @ts-ignore */}
                {charts.map((item: IChartChoice, index: number) => {
                    if (index !== selected) return null;

                    if (isCongressUserLocale && index === 1) {
                        return (
                            <div
                                key={index}
                                className="col hover-chart"
                                onClick={handleSetExpanded}
                            >
                                <item.Component
                                    key={index}
                                    score={collectDistrictScoresForState(
                                        locale,
                                        userVote,
                                        bill.score,
                                    )}
                                    billFirestoreId={bill.firestoreId}
                                    handleClick={handleSetExpanded}
                                    locale={setUserLocaleDistrictAsState(locale)}
                                    isEmptyScore={isEmptyScore(bill.score)}
                                />
                            </div>
                        );
                    }

                    return (
                        <div key={index} className="col hover-chart" onClick={handleSetExpanded}>
                            <item.Component
                                key={index}
                                score={updateBillScoreWithUserVote(
                                    locale,
                                    userVote,
                                    bill.score,
                                )}
                                billFirestoreId={bill.firestoreId}
                                handleClick={handleSetExpanded}
                                locale={locale}
                                isEmptyScore={isEmptyScore(bill.score)}
                            />
                        </div>
                    );
                })}
            </div>
            {selectedChart && (
                <DialogWrapper open={open} setOpen={handleClose}>
                    <selectedChart.Component
                        score={updateBillScoreWithUserVote(locale, userVote, bill.score)}
                        billFirestoreId={bill.firestoreId}
                        userLocale={locale}
                        isEmptyScore={isEmptyScore(bill.score)}
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillMobileChartsContainer;
