/** @format */

import { IconButton, SvgIconTypeMap, Typography } from "@material-ui/core";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { InsertChart, MapOutlined } from "@material-ui/icons";
import {
    get,
    getTextDistrict,
    isCongressLocale,
    isEmptyObject,
    titleize,
} from "@sway/utils";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { swayBlue } from "../../../utils";
import DialogWrapper from "../../dialogs/DialogWrapper";
import { SwaySvgIcon } from "../../SwaySvg";
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

const BillMobileChartsContainer: React.FC<IProps> = ({
    bill,
    userLocale,
    filter,
}) => {
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
                ? () => (
                      <SwaySvgIcon src={"/united_states.svg"} />
                  )
                : InsertChart,
            label: isCongressLocale(userLocale)
                ? "Congress Total"
                : `${titleize(userLocale.city)} Total`,
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

    const collectDistrictScoresForState = (
        score: sway.IBillScore,
    ): sway.IBillScore => {
        const district = getTextDistrict(userLocale.district) as string;

        return Object.keys(score.districts)
            .filter((k: string) => k.startsWith(district))
            .reduce(
                (sum: sway.IBillScore, key: string) => {
                    sum.districts[district].for =
                        Number(get(sum, `districts.${district}.for`) || 0) +
                        Number(get(score, `districts.${key}.for`) || 0);

                    sum.districts[district].against =
                        Number(get(sum, `districts.${district}.against`) || 0) +
                        Number(get(score, `districts.${key}.against`) || 0);

                    return sum;
                },
                {
                    districts: {
                        [district]: {
                            for: 0,
                            against: 0,
                        },
                    },
                } as sway.IBillScore,
            );
    };
    const setUserLocaleDistrictAsState = (): sway.IUserLocale => {
        return {
            ...userLocale,
            district: getTextDistrict(userLocale.district) as string,
        };
    };

    return (
        <div ref={ref} className={"charts-container bill-charts-container"}>
            <div className={"bill-charts-selector"}>
                {components
                    .filter(Boolean)
                    .map((item: IChartChoice | null, index: number) => {
                        if (!item) return false;
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
                .filter(Boolean)
                .filter((item: IChartChoice | null) => {
                    if (!item) return false;
                    if (filter) return filter && item.key === filter;
                    return true;
                })
                .map((item: IChartChoice | null, index: number) => {
                    if (!item) return null;
                    if (index !== selected) return null;

                    if (isCongressLocale(userLocale) && index === 1) {
                        return (
                            <div
                                key={index}
                                className="hover-chart"
                                onClick={handleSetExpanded}
                            >
                                <item.Component
                                    key={index}
                                    score={collectDistrictScoresForState(
                                        bill.score,
                                    )}
                                    billFirestoreId={bill.firestoreId}
                                    handleClick={handleSetExpanded}
                                    userLocale={setUserLocaleDistrictAsState()}
                                />
                            </div>
                        );
                    }

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

export default BillMobileChartsContainer;
