/** @format */

import { ROUTES } from "@sway/constants";
import { Typography } from "@material-ui/core";
import { sway } from "sway";
import React from "react";
import { Bubble, Pie } from "react-chartjs-2";
import { Link } from "react-router-dom";
import {
    bootsPalette,
    chartDimensions,
    floralPalette,
    rainbowPalette,
} from "../../../utils";
import { isEmptyObject } from "@sway/utils";
import { IChildChartProps } from "./BillChartsContainer";

export const PieAffinityChart: React.FC<IChildChartProps> = ({ score }) => {
    const districtScores: { [key: number]: sway.IBaseScore } = score.districts;
    if (isEmptyObject(districtScores)) {
        return (
            <>
                <Typography
                    style={{ textAlign: "center" }}
                    variant="body1"
                    color="textPrimary"
                    component="p"
                >
                    {
                        "We can't show a score because you haven't voted on any bills yet."
                    }
                </Typography>
                <Typography
                    style={{ textAlign: "center" }}
                    variant="body2"
                    color="textSecondary"
                    component="p"
                >
                    Click <Link to={ROUTES.pastBills}>here</Link> to start
                    voting!
                </Typography>
            </>
        );
    }

    const districtKeys = Object.keys(districtScores);

    const data = {
        labels: districtKeys.map((key: string): string => {
            const dscore: sway.IBaseScore = districtScores[Number(key)];
            const amount = Number(dscore.for) - Number(dscore.against);
            const symbol = amount > 0 ? "+" : "";
            return `D-${key} (${symbol}${amount})`;
        }),
        datasets: [
            {
                data: districtKeys.map((key: string): number => {
                    const dscore: sway.IBaseScore = districtScores[Number(key)];
                    return Number(dscore.for) - Number(dscore.against);
                }),
                backgroundColor: floralPalette
                    .concat(bootsPalette)
                    .concat(rainbowPalette),
                hoverBackgroundColor: "rebeccapurple",
            },
        ],
    };

    return (
        <Pie
            data={data}
            width={chartDimensions()}
            height={chartDimensions()}
            options={{
                maintainAspectRatio: false,
                layout: {
                    justifyContent: "center",
                    padding: 10,
                },
                scales: {
                    xAxes: [
                        {
                            gridLines: {
                                color: "rgba(0, 0, 0, 0)",
                            },
                        },
                    ],
                    yAxes: [
                        {
                            gridLines: {
                                color: "rgba(0, 0, 0, 0)",
                            },
                        },
                    ],
                },
            }}
        />
    );
};

interface IBubblePoint {
    x: number;
    y: number;
    r: number;
    label: string;
}

const BubbleAffinityChart: React.FC<IChildChartProps> = ({
    score,
    billFirestoreId,
}) => {
    const districtScores: { [key: number]: sway.IBaseScore } = score.districts;
    const districtKeys = Object.keys(districtScores);

    const data = {
        labels: districtKeys.map((key: string): string => {
            const dscore: sway.IBaseScore = districtScores[Number(key)];
            const amount = Number(dscore.for) - Number(dscore.against);
            const symbol = amount > 0 ? "+" : "";
            return `D-${key} (${symbol}${amount})`;
        }),
        datasets: [
            {
                label: `Affinity to ${billFirestoreId} By District`,
                data: districtKeys.map((key: string) => {
                    const dscore: sway.IBaseScore = districtScores[Number(key)];
                    const amount = Number(dscore.for) - Number(dscore.against);
                    const symbol = amount > 0 ? "+" : "";
                    return {
                        x: Number(key),
                        y: Number(dscore.for) - Number(dscore.against),
                        r: Number(key) === 0 ? 0 : 10,
                        label: `D-${key} (${symbol}${amount})`,
                    };
                }),
                fill: false,
                lineTension: 0.1,
                backgroundColor: "rgba(75,192,192,0.4)",
                borderColor: "rgba(75,192,192,1)",
                borderCapStyle: "butt",
                borderDash: [],
                borderDashOffset: 0.0,
                borderJoinStyle: "miter",
                pointBorderColor: "rgba(75,192,192,1)",
                pointBackgroundColor: "#fff",
                pointBorderWidth: 1,
                pointHoverRadius: 5,
                pointHoverBackgroundColor: "rgba(75,192,192,1)",
                pointHoverBorderColor: "rgba(220,220,220,1)",
                pointHoverBorderWidth: 2,
                pointRadius: 1,
                pointHitRadius: 10,
            },
        ],
    };

    const datasetData: number[] = data.datasets[0].data.map(
        (item: IBubblePoint) => item.y,
    );
    const max: number = Math.max(...datasetData) || 1;
    const min: number = Math.min(...datasetData) || -1;

    const rounded = (limit: number): number => {
        if (limit < 10) return 10;
        if (limit < 100) return 100;
        if (limit < 500) return 500;
        if (limit < 1000) return 1000;
        if (limit < 2000) return 2000;
        if (limit < 5000) return 5000;
        return 10000;
    };

    return (
        <Bubble
            data={data}
            width={chartDimensions()}
            height={chartDimensions()}
            options={{
                maintainAspectRatio: false,
                layout: {
                    justifyContent: "center",
                    padding: 10,
                },
                scales: {
                    xAxes: [
                        {
                            gridLines: {
                                color: "rgba(0, 0, 0, 0)",
                            },
                        },
                    ],
                    yAxes: [
                        {
                            ticks: {
                                min:
                                    Math.floor(min / rounded(min)) *
                                    rounded(min),
                                max:
                                    Math.ceil(max / rounded(max)) *
                                    rounded(max),
                            },
                            gridLines: {
                                color: "rgba(0, 0, 0, 0)",
                            },
                        },
                    ],
                },
            }}
        />
    );
};

export default BubbleAffinityChart;
