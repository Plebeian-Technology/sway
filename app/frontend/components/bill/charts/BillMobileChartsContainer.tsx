/** @format */

import { useLocale } from "app/frontend/hooks/useLocales";
import { SWAY_COLORS, isCongressLocale, titleize } from "app/frontend/sway_utils";
import { lazy, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { FiBarChart, FiBarChart2, FiFlag, FiMap } from "react-icons/fi";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";

import { isEmptyScore } from "../../../sway_utils/charts";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotes from "./TotalVotesChart";

import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { Button } from "react-bootstrap";
import { BillChartFilters } from "./constants";
import SuspenseFullScreen from "app/frontend/components/dialogs/SuspenseFullScreen";
const DialogWrapper = lazy(() => import("../../dialogs/DialogWrapper"));

interface IProps {
    bill: sway.IBill;
    filter?: string;
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

const BillMobileChartsContainer: React.FC<IProps> = ({ bill, filter }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [locale] = useLocale();
    const isCongressUserLocale = isCongressLocale(locale);

    const { items: billScore } = useAxiosGet<sway.IBillScore>(`/bill_scores/${bill?.id}`);

    // debugger;

    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(0);
    const [expanded, setExpanded] = useState<boolean>(false);

    const handleSetExpanded = useCallback(() => {
        setOpen(true);
        setExpanded(true);
    }, [setOpen]);

    const handleClose = useCallback(() => {
        setOpen(false);
        setExpanded(false);
    }, [setOpen]);

    const chartLabel = useMemo(() => {
        if (locale.regionName && !isCongressLocale) {
            return `${titleize(locale.regionName)} Total`;
        } else {
            return "Region Total";
        }
    }, [locale?.regionName]);

    const components = useMemo(
        () => [
            {
                key: BillChartFilters.district,
                Component: DistrictVotesChart,
                Icon: FiMap,
                label: "District Total",
                props: {
                    district: locale.districts.find((d) => d.number !== 0),
                },
            },
            isCongressUserLocale
                ? {
                      key: BillChartFilters.state,
                      Component: DistrictVotesChart,
                      Icon: FiBarChart,
                      label: chartLabel,
                      props: {
                          district: locale.districts.find((d) => d.number !== 0),
                      },
                  }
                : null,
            {
                key: BillChartFilters.total,
                Component: TotalVotes,
                Icon: isCongressUserLocale ? FiFlag : FiBarChart2,
                label: isCongressUserLocale ? "Congress Total" : `${titleize(locale?.city || "")} Total`,
                props: {
                    district: locale.districts.find((d) => d.number === 0),
                },
            },
        ],
        [locale, isCongressUserLocale, chartLabel],
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

    const selectedChart = useMemo(() => expanded && components[selected], [components, expanded, selected]);

    const chartsCount = useMemo(() => charts.length, [charts.length]);
    useEffect(() => {
        if (selected >= chartsCount) {
            setSelected(0);
        }
    }, [chartsCount, components, expanded, selected]);

    if (!billScore) return null;

    return (
        <div className="row my-4">
            <div ref={ref} className="col">
                <div className="row mb-2">
                    {/* @ts-expect-error - weird error with overlapping type interfaces */}
                    {charts.map((item: IChartChoice, index: number) => {
                        const isSelected = index === selected;
                        return (
                            <div
                                key={index}
                                className={`col text-center mx-2 ${isSelected ? "border-primary blue" : ""}`}
                            >
                                <Button
                                    onClick={() => setSelected(index)}
                                    variant="outline-primary"
                                    className="w-100"
                                    style={{
                                        color: index === selected ? SWAY_COLORS.white : SWAY_COLORS.primary,
                                        backgroundColor: index === selected ? SWAY_COLORS.primary : SWAY_COLORS.white,
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

                        if (isCongressUserLocale && index === 1) {
                            return (
                                <div // NOSONAR
                                    key={index}
                                    role="button"
                                    tabIndex={0}
                                    aria-pressed={expanded}
                                    aria-expanded={expanded}
                                    className="col hover-chart"
                                    onClick={handleSetExpanded}
                                    onKeyDown={handleSetExpanded}
                                >
                                    <item.Component
                                        key={index}
                                        score={billScore}
                                        bill={bill}
                                        handleClick={handleSetExpanded}
                                        isEmptyScore={isEmptyScore(billScore)}
                                        {...item.props}
                                    />
                                </div>
                            );
                        } else {
                            return (
                                <div // NOSONAR
                                    key={index}
                                    role="button"
                                    tabIndex={0}
                                    aria-pressed={expanded}
                                    aria-expanded={expanded}
                                    className="col hover-chart"
                                    onClick={handleSetExpanded}
                                    onKeyDown={handleSetExpanded}
                                >
                                    <item.Component
                                        key={index}
                                        bill={bill}
                                        score={billScore}
                                        handleClick={handleSetExpanded}
                                        isEmptyScore={isEmptyScore(billScore)}
                                        {...item.props}
                                    />
                                </div>
                            );
                        }
                    })}
                </div>
                {selectedChart && (
                    <SuspenseFullScreen>
                        <DialogWrapper open={open} setOpen={handleClose}>
                            <selectedChart.Component
                                bill={bill}
                                score={billScore}
                                isEmptyScore={isEmptyScore(billScore)}
                                district={selectedChart.props.district as sway.IDistrict}
                            />
                        </DialogWrapper>
                    </SuspenseFullScreen>
                )}
            </div>
        </div>
    );
};

export default BillMobileChartsContainer;
