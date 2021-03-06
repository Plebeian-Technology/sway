/** @format */

import { Typography } from "@material-ui/core";
import { ROUTES } from "@sway/constants";
import { isEmptyObject, isNumber } from "@sway/utils";
import React from "react";
import { Bar } from "react-chartjs-2";
import { Link } from "react-router-dom";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../utils";

interface IProps {
    scores:
        | sway.IAggregatedBillLocaleScores
        | undefined;
    title: string;
    colors: {
        primary: string;
        secondary: string;
    };
}

const VoterAgreementChart: React.FC<IProps> = ({ scores, title }) => {
    if (!scores) return null;

    if (!scores || isEmptyObject(scores)) {
        return (
            <>
                <Typography
                    style={{ textAlign: "center", marginTop: 5 }}
                    variant="body1"
                    color="textPrimary"
                    component="p"
                >
                    {"Chart available after voting on bill(s)."}
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

    const agreedScore = () => {
        if (isNumber(scores.totalAgreedDistrict)) {
            return scores.totalAgreedDistrict;
        }
        return 0;
    };

    const disagreedScore = () => {
        if (isNumber(scores.totalDisagreedDistrict)) {
            return scores.totalDisagreedDistrict;
        }
        return 0;
    };

    if (agreedScore() === 0 && disagreedScore() === 0) {
        return null;
    }

    const data = {
        labels: ["Agreed", "Disagreed"],
        datasets: [
            {
                label: "",
                backgroundColor: SWAY_COLORS.primaryLight,
                borderColor: SWAY_COLORS.primary,
                borderWidth: 1,
                hoverBackgroundColor: SWAY_COLORS.primaryLight,
                hoverBorderColor: SWAY_COLORS.primary,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Agreed", y: agreedScore() },
                    { x: "Disagreed", y: disagreedScore() },
                ],
            },
        ],
    };

    const max: number = Math.max(...[agreedScore(), disagreedScore()]);
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
                                color: SWAY_COLORS.transparent,
                            },
                        },
                    ],
                    xAxes: [
                        {
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

export default VoterAgreementChart;
