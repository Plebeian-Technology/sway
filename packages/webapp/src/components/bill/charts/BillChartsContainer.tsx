/** @format */

import {
    get,
    getTextDistrict,
    isCongressLocale,
    isEmptyObject,
} from "@sway/utils";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import DialogWrapper from "../../dialogs/DialogWrapper";
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
            {components
                .filter(Boolean)
                .filter((item: IChartChoice | null) => {
                    if (!item) return false;
                    if (filter) return filter && item.key === filter;
                    return true;
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
                                        bill.score,
                                    )}
                                    billFirestoreId={bill.firestoreId}
                                    userLocale={setUserLocaleDistrictAsState()}
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
