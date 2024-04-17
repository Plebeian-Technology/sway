/** @format */

import { isCongressLocale, isEmptyObject, logDev } from "app/frontend/sway_utils";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { isEmptyScore } from "../../../sway_utils/charts";
import DialogWrapper from "../../dialogs/DialogWrapper";
import {
    collectDistrictScoresForState,
    setUserLocaleDistrictAsState,
    updateBillScoreWithUserVote,
} from "./bill_chart_utils";
import { BillChartFilters } from "./constants";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotesChart from "./TotalVotesChart";

interface IProps {
    bill: sway.IBill;
    userLocale: sway.IUserLocale;
    userVote: sway.IUserVote;
    filter?: string;
}

export interface IChildChartProps {
    score: sway.IBillScore;
    billFirestoreId: string;
    userLocale: sway.IUserLocale;
    isEmptyScore: boolean;
}

interface IChartChoice {
    key: string;
    Component: React.FC<IChildChartProps>;
}

const BillChartsContainer: React.FC<IProps> = ({ bill, userLocale, userVote, filter }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(-1);

    const handleSetSelected = (index: number) => {
        setOpen(true);
        setSelected(index);
    };
    const handleClose = () => {
        setOpen(false);
        setSelected(-1);
    };

    const components = [
        { key: BillChartFilters.district, Component: DistrictVotesChart },
        isCongressLocale(userLocale)
            ? { key: BillChartFilters.state, Component: DistrictVotesChart }
            : null,
        { key: BillChartFilters.total, Component: TotalVotesChart },
    ];

    if (isEmptyObject(bill.score)) {
        logDev(`Empty bill scores for bill - ${bill.firestoreId} - skipping render bill charts.`);
        return null;
    }

    const selectedChart = selected > -1 && components[selected];

    const charts = [];
    for (const component of components) {
        if (component) {
            if (filter) {
                if (component?.key === filter) {
                    charts.push(component);
                } else {
                    // no-op, component key !== filter
                }
            } else {
                charts.push(component);
            }
        }
    }

    return (
        <div ref={ref} className="row">
            {charts.map((item: IChartChoice | null, index: number) => {
                if (!item) return null;
                if (isCongressLocale(userLocale) && index === 1) {
                    return (
                        <div
                            key={index}
                            className="col hover-chart"
                            onClick={() => handleSetSelected(index)}
                        >
                            <item.Component
                                score={collectDistrictScoresForState(
                                    userLocale,
                                    userVote,
                                    bill.score,
                                )}
                                billFirestoreId={bill.firestoreId}
                                userLocale={setUserLocaleDistrictAsState(userLocale)}
                                isEmptyScore={isEmptyScore(bill.score)}
                            />
                        </div>
                    );
                }
                return (
                    <div
                        key={index}
                        className="col hover-chart"
                        onClick={() => handleSetSelected(index)}
                    >
                        <item.Component
                            score={updateBillScoreWithUserVote(userLocale, userVote, bill.score)}
                            billFirestoreId={bill.firestoreId}
                            userLocale={userLocale}
                            isEmptyScore={isEmptyScore(bill.score)}
                        />
                    </div>
                );
            })}
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

export default BillChartsContainer;
