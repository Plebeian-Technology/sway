/** @format */

import { sway } from "sway";
import React from "react";
import { Line } from "react-chartjs-2";
import {
    chartDimensions,
    swayGreen,
    swayPurple,
    swayRed,
    swaySelectedRed,
    selectedGreen,
    SWAY_COLORS,
} from "../../../utils";
import { IAggregateResponseData } from "../LegislatorCard";

interface IProps {
    scores: IAggregateResponseData;
    title: string;
    colors: sway.IPlainObject;
}

const VoterPercentileChart: React.FC<IProps> = ({ scores, title }) => {
    const sortedAgreedPercentsRadius: number[] = scores.sortedAgreedPercents.map(
        (n: number) => (n === scores.userAgreedPercentile ? 5 : 1)
    );
    const sortedDisagreedPercentsRadius: number[] = scores.sortedDisagreedPercents.map(
        (n: number) => (n === scores.userDisagreedPercentile ? 5 : 1)
    );
    // const sortedAbstainedPercentsRadius: number[] = scores.sortedAbstainedPercents.map(
    //     (n: number) => (n === scores.userAbstainedPercentile ? 5 : 1)
    // );
    const sortedAgreedPercentsColor: string[] = scores.sortedAgreedPercents.map(
        (n: number) =>
            n === scores.userAgreedPercentile ? swayPurple : swayGreen
    );
    const sortedDisagreedPercentsColor: string[] = scores.sortedDisagreedPercents.map(
        (n: number) =>
            n === scores.userDisagreedPercentile ? swayPurple : swayRed
    );
    // const sortedAbstainedPercentsColor: string[] = scores.sortedAbstainedPercents.map(
    //     (n: number) =>
    //         n === scores.userAbstainedPercentile ? swayPurple : swayBlue
    // );

    const data = {
        datasets: [
            {
                label: "Agreement",
                backgroundColor: selectedGreen,
                borderColor: swayGreen,
                data: scores.sortedAgreedPercents.map(
                    (n: number, i: number) => ({
                        x: i,
                        y: n,
                    })
                ),
                fill: false,
                pointBorderColor: sortedAgreedPercentsColor,
                pointBackgroundColor: sortedAgreedPercentsColor,
                pointBorderWidth: sortedAgreedPercentsRadius,
                pointHoverBorderWidth: 10,
            },
            {
                label: "Disagreement",
                backgroundColor: swaySelectedRed,
                borderColor: swayRed,
                data: scores.sortedDisagreedPercents.map(
                    (n: number, i: number) => ({
                        x: i,
                        y: n,
                    })
                ),
                fill: false,
                pointBorderColor: sortedDisagreedPercentsColor,
                pointBackgroundColor: sortedDisagreedPercentsColor,
                pointBorderWidth: sortedDisagreedPercentsRadius,
                pointHoverBorderWidth: 10,
            },
            // {
            //     label: "Abstention",
            //     backgroundColor: selectedBlue,
            //     borderColor: swayBlue,
            //     data: scores.sortedAbstainedPercents.map(
            //         (n: number, i: number) => ({
            //             x: i,
            //             y: n,
            //         })
            //     ),
            //     fill: false,
            //     pointBorderColor: sortedAbstainedPercentsColor,
            //     pointBackgroundColor: sortedAbstainedPercentsColor,
            //     pointBorderWidth: sortedAbstainedPercentsRadius,
            //     pointHoverBorderWidth: 10,
            // },
        ],
    };

    const userTooltipTitle = (tooltip: { datasetIndex: number, yLabel: string }) => {
        const item = tooltip[0];
        if (
            item.datasetIndex === 0 &&
            item.yLabel === scores.userAgreedPercentile
        ) {
            return "Your Agreed Percent";
        }
        if (
            item.datasetIndex === 1 &&
            item.yLabel === scores.userDisagreedPercentile
        ) {
            return "Your Disagreed Percent";
        }
        if (
            item.datasetIndex === 2 &&
            item.yLabel === scores.userAbstainedPercentile
        ) {
            return "Your Abstained Percent";
        }

        return "";
    };

    // NOTE: For making sure all points show up on lines:
    // https://stackoverflow.com/a/57130191/6410635
    return (
        <Line
            width={chartDimensions()}
            height={chartDimensions()}
            data={data}
            options={{
                title: {
                    text: title,
                    display: true,
                },
                tooltips: {
                    callbacks: {
                        title: userTooltipTitle,
                    },
                },
                maintainAspectRatio: false,
                scales: {
                    xAxes: [
                        {
                            type: "linear",
                            display: true,
                            gridLines: {
                                color: SWAY_COLORS.transparent,
                            },
                            scaleLabel: {
                                display: true,
                            },
                        },
                    ],
                    yAxes: [
                        {
                            display: true,
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

export default VoterPercentileChart;
