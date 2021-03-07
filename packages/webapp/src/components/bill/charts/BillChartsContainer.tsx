/** @format */

import { useRef, useState } from "react";
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
    userLocale: sway.IUserLocale;
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

const BillChartsContainer: React.FC<IProps> = ({ bill, userLocale, filter }) => {
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
        { key: BillChartFilters.total, Component: TotalVotes },
        { key: BillChartFilters.district, Component: DistrictVotes },
    ];

    if (isEmptyObject(bill.score)) return null;

    const selectedChart = selected > -1 && components[selected];

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
                                userLocale={userLocale}
                            />
                        </div>
                    );
                })}
            {selectedChart && (
                <DialogWrapper open={open} setOpen={handleClose}>
                    <selectedChart.Component
                        score={bill.score}
                        billFirestoreId={bill.firestoreId}
                        userLocale={userLocale}
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillChartsContainer;
