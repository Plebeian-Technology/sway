/** @format */

import { isCongressLocale, isEmptyObject } from "@sway/utils";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import DialogWrapper from "../../dialogs/DialogWrapper";
import {
    collectDistrictScoresForState,
    setUserLocaleDistrictAsState,
    updateBillScoreWithUserVote,
} from "./bill_chart_utils";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotesChart from "./TotalVotesChart";

export const BillChartFilters: {
    total: "total";
    bubble_districts: "bubble_districts";
    district: "district";
    state: "state";
} = {
    total: "total",
    bubble_districts: "bubble_districts",
    district: "district",
    state: "state",
};

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
}

interface IChartChoice {
    key: string;
    Component: React.FC<IChildChartProps>;
}

const BillChartsContainer: React.FC<IProps> = ({
    bill,
    userLocale,
    userVote,
    filter,
}) => {
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

    if (isEmptyObject(bill.score)) return null;

    const selectedChart = selected > -1 && components[selected];

    return (
        <div ref={ref} className={"charts-container bill-charts-container"}>
            {components
                .filter(Boolean)
                .filter((item: IChartChoice | null) => {
                    if (filter) return filter && item?.key === filter;
                    return !!item;
                })
                .map((item: IChartChoice | null, index: number) => {
                    if (!item) return null;
                    if (isCongressLocale(userLocale) && index === 1) {
                        return (
                            <div
                                key={index}
                                className="hover-chart"
                                onClick={() => handleSetSelected(index)}
                            >
                                <item.Component
                                    score={collectDistrictScoresForState(
                                        userLocale,
                                        userVote,
                                        bill.score,
                                    )}
                                    billFirestoreId={bill.firestoreId}
                                    userLocale={setUserLocaleDistrictAsState(
                                        userLocale,
                                    )}
                                />
                            </div>
                        );
                    }
                    return (
                        <div
                            key={index}
                            className="hover-chart"
                            onClick={() => handleSetSelected(index)}
                        >
                            <item.Component
                                score={updateBillScoreWithUserVote(
                                    userLocale,
                                    userVote,
                                    bill.score,
                                )}
                                billFirestoreId={bill.firestoreId}
                                userLocale={userLocale}
                            />
                        </div>
                    );
                })}
            {selectedChart && (
                <DialogWrapper open={open} setOpen={handleClose}>
                    <selectedChart.Component
                        score={updateBillScoreWithUserVote(
                            userLocale,
                            userVote,
                            bill.score,
                        )}
                        billFirestoreId={bill.firestoreId}
                        userLocale={userLocale}
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillChartsContainer;
