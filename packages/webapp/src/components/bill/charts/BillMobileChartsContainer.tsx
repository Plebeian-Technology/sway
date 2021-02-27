/** @format */

import { IconButton, SvgIconTypeMap, Typography } from "@material-ui/core";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { InsertChart, MapOutlined } from "@material-ui/icons";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { swayBlue } from "../../../utils";
import { isEmptyObject } from "@sway/utils";
import DialogWrapper from "../../dialogs/DialogWrapper";
import DistrictVotes from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";
import { useRef, useState } from "react";

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
    selected?: true;
    handleClick: (index: number) => void;
}

interface IChartChoice {
    key: string;
    label: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    Component: React.FC<IChildChartProps>;
}

const BillMobileChartsContainer: React.FC<IProps> = ({ bill, filter }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(0);
    const [expanded, setExpanded] = useState<boolean>(false);

    const handleSetExpanded = () => {
        setOpen(true);
        setExpanded(true);
    };
    const handleClose = () => {
        setOpen(false);
        setExpanded(false);
    };

    const components = [
        {
            key: BillChartFilters.total,
            Component: TotalVotes,
            Icon: InsertChart,
            label: "Total Votes",
        },
        {
            key: BillChartFilters.district,
            Component: DistrictVotes,
            Icon: MapOutlined,
            label: "District Total",
        },
    ];

    const selectedChart = expanded && components[selected];

    if (isEmptyObject(bill.score)) return null;

    const style = (index: number) => {
        if (index === selected) {
            if (index === 0) {
                return {
                    border: `2px solid ${swayBlue}`,
                    paddingLeft: 20,
                    paddingRight: 20,
                };
            }
            return {
                border: `2px solid ${swayBlue}`,
            };
        }
        return {};
    };

    return (
        <div ref={ref} className={"charts-container bill-charts-container"}>
            <div className={"bill-charts-selector"}>
                {components.map((item: IChartChoice, index: number) => {
                    return (
                        <div
                            key={index}
                            onClick={() => setSelected(index)}
                            className={"bill-charts-selector-child"}
                            style={style(index)}
                        >
                            <Typography component={"p"} variant={"body2"}>
                                {item.label}
                            </Typography>
                            <IconButton
                                onClick={() => setSelected(index)}
                                aria-label={item.label}
                                style={{ padding: 0 }}
                            >
                                {
                                    <item.Icon
                                        style={{
                                            color:
                                                index === selected
                                                    ? swayBlue
                                                    : "initial",
                                        }}
                                    />
                                }
                            </IconButton>
                        </div>
                    );
                })}
            </div>
            {components
                .filter((item: IChartChoice) => {
                    if (filter) return filter && item.key === filter;
                    return true;
                })
                .map((item: IChartChoice, index: number) => {
                    if (index !== selected) return null;

                    return (
                        <div
                            key={index}
                            className="hover-chart"
                            onClick={handleSetExpanded}
                        >
                            <item.Component
                                key={index}
                                score={bill.score}
                                billFirestoreId={bill.firestoreId}
                                handleClick={handleSetExpanded}
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

export default BillMobileChartsContainer;
