/** @format */

import { STATE_CODES_NAMES } from "@sway/constants";
import { getTextDistrict, isEmptyObject, titleize } from "@sway/utils";
import { useCallback, useMemo, useRef, useState } from "react";
import { FiBarChart, FiBarChart2, FiFlag, FiMap } from "react-icons/fi";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { useIsCongressUserLocale, useUserLocale } from "../../../hooks/locales/useUserLocale";
import { swayBlue } from "../../../utils";
import { isEmptyScore } from "../../../utils/charts";
import DialogWrapper from "../../dialogs/DialogWrapper";
import {
    collectDistrictScoresForState,
    setUserLocaleDistrictAsState,
    updateBillScoreWithUserVote,
} from "./bill_chart_utils";
import { BillChartFilters } from "./constants";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";

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
    userLocale: sway.IUserLocale;
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
    const userLocale = useUserLocale();
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

    const districtChartLabel = useMemo(() => {
        if (!userLocale?.district) return "";

        const textDistrict = getTextDistrict(userLocale.district);
        if (textDistrict) {
            return `${STATE_CODES_NAMES[textDistrict]} Total`;
        } else {
            return "Region Total";
        }
    }, [userLocale?.district]);

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
                    : `${titleize(userLocale?.city || "")} Total`,
            },
        ],
        [userLocale?.city, isCongressUserLocale, districtChartLabel],
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

    if (!userVote || !userLocale) return null;
    if (isEmptyObject(bill.score)) return null;

    return (
        <div ref={ref} className="col">
            <div className="row mb-2">
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
                                        userLocale,
                                        userVote,
                                        bill.score,
                                    )}
                                    billFirestoreId={bill.firestoreId}
                                    handleClick={handleSetExpanded}
                                    userLocale={setUserLocaleDistrictAsState(userLocale)}
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
                                    userLocale,
                                    userVote,
                                    bill.score,
                                )}
                                billFirestoreId={bill.firestoreId}
                                handleClick={handleSetExpanded}
                                userLocale={userLocale}
                                isEmptyScore={isEmptyScore(bill.score)}
                            />
                        </div>
                    );
                })}
            </div>
            {selectedChart && (
                <DialogWrapper open={open} setOpen={handleClose}>
                    <selectedChart.Component
                        score={updateBillScoreWithUserVote(userLocale, userVote, bill.score)}
                        billFirestoreId={bill.firestoreId}
                        userLocale={userLocale}
                        isEmptyScore={isEmptyScore(bill.score)}
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillMobileChartsContainer;
