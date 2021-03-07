/** @format */

import { Typography } from "@material-ui/core";
import { ROUTES } from "@sway/constants";
import { getNumericDistrict, isEmptyObject } from "@sway/utils";
import React from "react";
import { Bar } from "react-chartjs-2";
import { Link } from "react-router-dom";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../utils";
import { IChildChartProps } from "./BillChartsContainer";

const DistrictVoteChart: React.FC<IChildChartProps> = ({
    score,
    billFirestoreId,
    userLocale,
}) => {
    const district: string = userLocale.district;
    const districtScore: sway.IBaseScore = score.districts[district];

    if (isEmptyObject(districtScore)) {
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

    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: `District ${getNumericDistrict(district)} Votes Cast on ${billFirestoreId}`,
                backgroundColor: SWAY_COLORS.primaryLight,
                borderColor: SWAY_COLORS.primary,
                borderWidth: 1,
                hoverBackgroundColor: SWAY_COLORS.primaryLight,
                hoverBorderColor: SWAY_COLORS.primary,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Support", y: districtScore.for || 0 },
                    { x: "Oppose", y: districtScore.against || 0 },
                ],
            },
        ],
    };

    const max: number = Math.max(
        ...[Number(districtScore.for || 0), Number(districtScore.against || 0)],
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

export default DistrictVoteChart;
