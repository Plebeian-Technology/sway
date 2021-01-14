/** @format */

import React from "react";
import { Bar } from "react-chartjs-2";
import {
    chartDimensions,
    swayLightPurple,
    swayPurple,
} from "../../../utils";
import { IChildChartProps } from "./BillChartsContainer";

const TotalVotesChart: React.FC<IChildChartProps> = ({
    score,
    billFirestoreId,
}) => {
    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: `Total Votes Cast on ${billFirestoreId}`,
                backgroundColor: swayLightPurple,
                borderColor: swayPurple,
                borderWidth: 1,
                hoverBackgroundColor: swayLightPurple,
                hoverBorderColor: swayPurple,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Support", y: score.for },
                    { x: "Oppose", y: score.against },
                ],
            },
        ],
    };

    const max: number = Math.max(...[Number(score.for), Number(score.against)]);
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
                                color: "rgba(0, 0, 0, 0)",
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
                                color: "rgba(0, 0, 0, 0)",
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
