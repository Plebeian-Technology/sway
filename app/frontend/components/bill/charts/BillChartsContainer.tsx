/** @format */

import { usePage } from "@inertiajs/react";
import SwayLoading from "app/frontend/components/SwayLoading";
import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { isCongressLocale, isEmptyObject, logDev } from "app/frontend/sway_utils";
import { useMemo, useRef } from "react";
import { sway } from "sway";
import { isEmptyScore } from "../../../sway_utils/charts";
import { BillChartFilters } from "./constants";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotesChart from "./TotalVotesChart";

interface IProps {
    bill: sway.IBill;
    locale: sway.ISwayLocale;
    user_vote: sway.IUserVote;
    filter?: string;
    onScoreReceived: () => void;
}

export interface IChildChartProps {
    bill: sway.IBill;
    score: sway.IBillScore;
    district: sway.IDistrict;
    isEmptyScore: boolean;
}

interface IChartChoice {
    key: string;
    Component: React.FC<IChildChartProps>;
    props: { district: sway.IDistrict };
}

const BillChartsContainer: React.FC<IProps> = ({ bill, locale, filter, onScoreReceived }) => {
    const districts = usePage().props.districts as sway.IDistrict[];
    const ref = useRef<HTMLDivElement | null>(null);

    const options = useMemo(() => ({ callback: onScoreReceived }), [onScoreReceived]);
    const { items: bill_score } = useAxiosGet<sway.IBillScore>(`/bill_scores/${bill.id}`, options);

    const components = [
        {
            key: BillChartFilters.district,
            Component: DistrictVotesChart,
            props: {
                district: districts.find((d) => d.number !== 0) as sway.IDistrict,
            },
        },
        isCongressLocale(locale)
            ? {
                  key: BillChartFilters.state,
                  Component: DistrictVotesChart,
                  props: {
                      district: districts.find((d) => d.number !== 0) as sway.IDistrict,
                  },
              }
            : null,
        {
            key: BillChartFilters.total,
            Component: TotalVotesChart,
            props: {
                district: districts.find((d) => d.number === 0) as sway.IDistrict,
            },
        },
    ];

    if (isEmptyObject(bill_score)) {
        logDev(`Empty bill scores for bill - ${bill.external_id} - skipping render bill charts.`);
        return null;
    }

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

    if (!bill_score) {
        return <SwayLoading />;
    }

    return (
        <div ref={ref} className="row">
            {charts.map((item: IChartChoice | null, index: number) => {
                if (!item) return null;

                return (
                    <item.Component
                        key={index}
                        score={bill_score}
                        bill={bill}
                        isEmptyScore={isEmptyScore(bill_score)}
                        district={item.props.district as sway.IDistrict}
                    />
                );
            })}
        </div>
    );
};

export default BillChartsContainer;
