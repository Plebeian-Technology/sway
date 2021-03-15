/** @format */

import { isCongressLocale, titleize } from "@sway/utils";
import React from "react";
import { Bar } from "react-chartjs-2";
import { chartDimensions, SWAY_COLORS } from "../../../utils";
import { IChildChartProps } from "./BillChartsContainer";

const TotalVotesChart: React.FC<IChildChartProps> = ({
    score,
    billFirestoreId,
    userLocale,
}) => {
    const location = isCongressLocale(userLocale)
        ? "the United States"
        : titleize(userLocale.city);
    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: `All Votes Cast in ${location} on ${billFirestoreId}`,
                backgroundColor: isCongressLocale(userLocale)
                    ? SWAY_COLORS.primaryLight
                    : SWAY_COLORS.primary,
                borderColor: SWAY_COLORS.primary,
                borderWidth: 1,
                hoverBackgroundColor: isCongressLocale(userLocale)
                    ? SWAY_COLORS.primaryLight
                    : SWAY_COLORS.primary,
                hoverBorderColor: SWAY_COLORS.primary,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Support", y: score.for || 0 },
                    { x: "Oppose", y: score.against || 0 },
                ],
            },
        ],
    };

    const max: number = Math.max(
        ...[Number(score.for || 0), Number(score.against || 0)],
    );
    const roundTo: number = ((_max: number) => {
        if (_max < 10) return 10;
        if (_max < 100) return 100;
        if (_max < 500) return 500;
        if (_max < 1000) return 1000;
        if (_max < 2000) return 2000;
        if (_max < 5000) return 5000;
        return 10000;
    })(max);

    return (
        <Bar
            width={chartDimensions()}
            height={chartDimensions()}
            data={data}
            options={{
                maintainAspectRatio: false,
                scales: {
                    xAxes: [
                        {
                            gridLines: {
                                color: SWAY_COLORS.transparent,
                            },
                        },
                    ],
                    yAxes: [
                        {
                            ticks: {
                                min: 0,
                                max: Math.ceil(max / roundTo) * roundTo,
                            },
                            gridLines: {
                                color: SWAY_COLORS.transparent,
                            },
                        },
                    ],
                },
                layout: {
                    padding: 10,
                },
            }}
        />
    );
};

export default TotalVotesChart;
