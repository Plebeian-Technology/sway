/** @format */

import { ROUTES } from "@sway/constants";
import { Typography } from "@material-ui/core";
import { sway } from "sway";
import React from "react";
import { Bar } from "react-chartjs-2";
import { Link } from "react-router-dom";
import { chartDimensions } from "../../../utils";
import { isEmptyObject } from "@sway/utils"

interface IProps {
    scores: sway.IUserLegislatorScore;
    title: string;
    colors: {
        primary: string;
        secondary: string;
    };
}

const VoterAgreementChart: React.FC<IProps> = ({ scores, title, colors }) => {
    if (isEmptyObject(scores) || scores.totalUserVotes === 0) {
        return (
            <>
                <Typography
                    style={{ textAlign: "center", marginTop: 5 }}
                    variant="body1"
                    color="textPrimary"
                    component="p"
                >
                    {
                        "Chart available after voting on bill(s)."
                    }
                </Typography>
                <Typography
                    style={{ textAlign: "center" }}
                    variant="body2"
                    color="textSecondary"
                    component="p"
                >
                    Click <Link to={ROUTES.billOfTheWeek}>here</Link> to start
                    voting!
                </Typography>
            </>
        );
    }

    const data = {
        labels: ["Agreed", "Disagreed", "No Legislator Vote", "Neither Voted"],
        datasets: [
            {
                label: "",
                backgroundColor: colors.primary,
                borderColor: colors.secondary,
                borderWidth: 1,
                hoverBackgroundColor: colors.primary,
                hoverBorderColor: colors.secondary,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Agreed", y: scores.totalUserLegislatorAgreed },
                    { x: "Disagreed", y: scores.totalUserLegislatorDisagreed },
                    {
                        x: "No Legislator Vote",
                        y: scores.totalUnmatchedLegislatorVote,
                    },
                    {
                        x: "Neither Voted",
                        y: scores.totalUserLegislatorAbstained,
                    },
                ],
            },
        ],
    };

    const max: number = Math.max(
        ...[
            Number(scores.totalUserLegislatorAgreed),
            Number(scores.totalUserLegislatorDisagreed),
            Number(scores.totalUnmatchedLegislatorVote),
            Number(scores.totalUserLegislatorAbstained),
        ]
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
                title: {
                    display: true,
                    text: title,
                },
                legend: {
                    display: false,
                },
                maintainAspectRatio: false,
                scales: {
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
                    xAxes: [
                        {
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

export default VoterAgreementChart;
