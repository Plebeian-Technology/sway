/** @format */

import { InsertChart, MapOutlined } from "@mui/icons-material";
import { IconButton, SvgIconTypeMap } from "@mui/material";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import { getTextDistrict, isCongressLocale, isEmptyObject, titleize } from "@sway/utils";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { swayBlue } from "../../../utils";
import DialogWrapper from "../../dialogs/DialogWrapper";
import { SwaySvgIcon } from "../../SwaySvg";
import {
    collectDistrictScoresForState,
    setUserLocaleDistrictAsState,
    updateBillScoreWithUserVote,
} from "./bill_chart_utils";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";

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
    selected?: true;
    handleClick: (index: number) => void;
    userLocale: sway.IUserLocale;
}

interface IChartChoice {
    key: string;
    label: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    Component: React.FC<IChildChartProps>;
}

const BillMobileChartsContainer: React.FC<IProps> = ({ bill, userLocale, userVote, filter }) => {
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

    const getStateTotalLabel = () => {
        const textDistrict = getTextDistrict(userLocale.district);
        return `${textDistrict} Total`;
    };

    const components = [
        {
            key: BillChartFilters.district,
            Component: DistrictVotesChart,
            Icon: MapOutlined,
            label: "District Total",
        },
        isCongressLocale(userLocale)
            ? {
                  key: BillChartFilters.state,
                  Component: DistrictVotesChart,
                  Icon: InsertChart,
                  label: getStateTotalLabel(),
              }
            : null,
        {
            key: BillChartFilters.total,
            Component: TotalVotes,
            Icon: isCongressLocale(userLocale)
                ? () => <SwaySvgIcon src={"/united_states.svg"} />
                : InsertChart,
            label: isCongressLocale(userLocale)
                ? "Congress Total"
                : `${titleize(userLocale.city)} Total`,
        },
    ];

    const selectedChart = expanded && components[selected];

    if (isEmptyObject(bill.score)) return null;

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
        <div ref={ref} className="col">
            <div className="row">
                {charts.map((item: IChartChoice, index: number) => {
                    const isSelected = index === selected;
                    return (
                        <div
                            key={index}
                            onClick={() => setSelected(index)}
                            className={`col text-center border border-2 rounded mx-2 ${
                                isSelected ? "border-primary blue" : ""
                            }`}
                        >
                            <div className="row g-0">
                                <div className="col">{item.label}</div>
                            </div>
                            <div className="row g-0">
                                <IconButton
                                    onClick={() => setSelected(index)}
                                    aria-label={item.label}
                                >
                                    {
                                        <item.Icon
                                            style={{
                                                color: index === selected ? swayBlue : "initial",
                                            }}
                                        />
                                    }
                                </IconButton>
                            </div>
                        </div>
                    );
                })}
            </div>
            {charts.map((item: IChartChoice, index: number) => {
                if (index !== selected) return null;

                if (isCongressLocale(userLocale) && index === 1) {
                    return (
                        <div key={index} className="col hover-chart" onClick={handleSetExpanded}>
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
                            />
                        </div>
                    );
                }

                return (
                    <div key={index} className="col hover-chart" onClick={handleSetExpanded}>
                        <item.Component
                            key={index}
                            score={updateBillScoreWithUserVote(userLocale, userVote, bill.score)}
                            billFirestoreId={bill.firestoreId}
                            handleClick={handleSetExpanded}
                            userLocale={userLocale}
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
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillMobileChartsContainer;
