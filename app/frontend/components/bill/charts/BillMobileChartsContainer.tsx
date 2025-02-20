/** @format */

import { useLocale } from "app/frontend/hooks/useLocales";
import { SWAY_COLORS, isCongressLocale, titleize } from "app/frontend/sway_utils";
import { PropsWithChildren, useEffect, useMemo, useRef, useState } from "react";
import { FiBarChart, FiBarChart2, FiFlag, FiMap } from "react-icons/fi";
import { sway } from "sway";

import { isEmptyScore } from "../../../sway_utils/charts";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";

import { usePage } from "@inertiajs/react";
import { Button } from "react-bootstrap";
import { BillChartFilters } from "./constants";

interface IProps extends PropsWithChildren {
    bill: sway.IBill;
    bill_score?: sway.IBillScore;
    filter?: string;
    onScoreReceived: () => void;
}

export interface IChildChartProps {
    score: sway.IBillScore;
    bill: sway.IBill;
    selected?: true;
    handleClick: (index: number) => void;
    isEmptyScore: boolean;
}

interface IChartChoice {
    key: string;
    label: string;
    Icon: React.FC<any>;
    Component: React.FC<IChildChartProps>;
    props: {
        district: sway.IDistrict;
    };
}

const BillMobileChartsContainer: React.FC<IProps> = ({ bill, bill_score, filter, onScoreReceived, children }) => {
    const districts = usePage().props.districts as sway.IDistrict[];
    const ref = useRef<HTMLDivElement | null>(null);
    const [locale] = useLocale();
    const isCongressUserLocale = isCongressLocale(locale);

    useEffect(() => {
        if (!!bill_score) {
            onScoreReceived();
        }
    }, [bill_score, onScoreReceived]);

    // const options = useMemo(() => ({ callback: onScoreReceived }), [onScoreReceived]);
    // const { items: bill_score } = useAxiosGet<sway.IBillScore>(`/bill_scores/${bill?.id}`, options);

    const [selected, setSelected] = useState<number>(0);

    const chartLabel = useMemo(() => {
        if (locale.region_name && !isCongressLocale) {
            return `${titleize(locale.region_name)} Total`;
        } else {
            return "Region Total";
        }
    }, [locale?.region_name]);

    const atLargeDistrict = districts.find((d) => d.number === 0);
    const specificDistrict = districts.find((d) => d.number !== 0);

    const components = useMemo(
        () => [
            specificDistrict
                ? {
                      key: BillChartFilters.district,
                      Component: DistrictVotesChart,
                      Icon: FiMap,
                      label: "District Total",
                      props: {
                          district: specificDistrict,
                      },
                  }
                : null,
            isCongressUserLocale
                ? {
                      key: BillChartFilters.state,
                      Component: DistrictVotesChart,
                      Icon: FiBarChart,
                      label: chartLabel,
                      props: {
                          district: specificDistrict,
                      },
                  }
                : null,
            atLargeDistrict
                ? {
                      key: BillChartFilters.total,
                      Component: TotalVotes,
                      Icon: isCongressUserLocale ? FiFlag : FiBarChart2,
                      label: isCongressUserLocale ? "Congress Total" : `${titleize(locale?.city || "")} Total`,
                      props: {
                          district: atLargeDistrict,
                      },
                  }
                : null,
        ],
        [specificDistrict, isCongressUserLocale, chartLabel, atLargeDistrict, locale?.city],
    );

    const charts = useMemo(() => {
        const charts_ = [];
        for (const component of components) {
            if (component) {
                if (filter) {
                    if (component?.key === filter) {
                        charts_.push(component);
                    } else {
                        // no-op, component key !== filter
                    }
                } else {
                    charts_.push(component);
                }
            }
        }
        return charts_;
    }, [components, filter]);

    if (!bill_score) return null;

    return (
        <div className="row my-4">
            <div ref={ref} className="col">
                {children}
                <div className="row mb-2">
                    {/* @ts-expect-error - weird error with overlapping type interfaces */}
                    {charts.map((item: IChartChoice, index: number) => {
                        const isSelected = index === selected;
                        return (
                            <div key={index} className={`col text-center ${isSelected ? "border-primary blue" : ""}`}>
                                <Button
                                    onClick={() => setSelected(index)}
                                    variant="outline-primary"
                                    className="w-100 mb-2"
                                    style={{
                                        color: index === selected ? SWAY_COLORS.white : SWAY_COLORS.primary,
                                        backgroundColor: index === selected ? SWAY_COLORS.primary : SWAY_COLORS.white,
                                        maxWidth: charts.length === 1 ? "400px" : undefined,
                                    }}
                                >
                                    <div>{item.label}</div>
                                    <div>
                                        <item.Icon
                                            style={{
                                                color: index === selected ? SWAY_COLORS.white : SWAY_COLORS.primary,
                                                backgroundColor:
                                                    index === selected ? SWAY_COLORS.primary : SWAY_COLORS.white,
                                            }}
                                        />
                                    </div>
                                </Button>
                            </div>
                        );
                    })}
                </div>
                <div className="row">
                    {/* @ts-expect-error - weird error with overlapping type interfaces */}
                    {charts.map((item: IChartChoice, index: number) => {
                        if (index !== selected) return null;

                        return (
                            <item.Component
                                key={index}
                                bill={bill}
                                score={bill_score}
                                handleClick={() => null}
                                isEmptyScore={isEmptyScore(bill_score)}
                                {...item.props}
                            />
                        );
                    })}
                </div>
            </div>
        </div>
    );
};

export default BillMobileChartsContainer;
