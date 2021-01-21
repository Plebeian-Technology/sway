/** @format */

import React from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { isEmptyObject } from "@sway/utils";
import DialogWrapper from "../../dialogs/DialogWrapper";
import DistrictVotes from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";

export const BillChartFilters: {
    total: "total";
    bubble_districts: "bubble_districts";
    district: "district";
} = {
    total: "total",
    bubble_districts: "bubble_districts",
    district: "district",
};

interface IProps {
    bill: sway.IBill;
    filter?: string;
}

export interface IChildChartProps {
    score: sway.IBillScore;
    billFirestoreId: string;
}

interface IChartChoice {
    key: string;
    Component: React.FC<IChildChartProps>;
}

const BillChartsContainer: React.FC<IProps> = ({ bill, filter }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = React.useRef(
        null,
    );
    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = React.useState<number | null>(null);

    const handleSetSelected = (index: number) => {
        setOpen(true);
        setSelected(index);
    };
    const handleClose = () => {
        setOpen(false);
        setSelected(null);
    };

    const components = [
        { key: BillChartFilters.total, Component: TotalVotes },
        { key: BillChartFilters.district, Component: DistrictVotes },
    ];

    if (isEmptyObject(bill.score)) return null;

    const selectedChart = selected && components[selected];

    return (
        <div ref={ref} className={"charts-container bill-charts-container"}>
            {components
                .filter((item: IChartChoice) => {
                    if (filter) return filter && item.key === filter;
                    return true;
                })
                .map((item: IChartChoice, index: number) => {
                    return (
                        <div
                            key={index}
                            className="hover-chart"
                            onClick={() => handleSetSelected(index)}
                        >
                            <item.Component
                                score={bill.score}
                                billFirestoreId={bill.firestoreId}
                            />
                        </div>
                    );
                })}
            {selectedChart && (
                <DialogWrapper open={open} setOpen={handleClose}>
                    <selectedChart.Component
                        score={bill.score}
                        billFirestoreId={bill.firestoreId}
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillChartsContainer;
