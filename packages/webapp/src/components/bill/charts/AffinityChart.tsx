/** @format */

import { ROUTES } from "@sway/constants";
import { isEmptyObject } from "@sway/utils";
import { ArcElement, Chart as ChartJS, Legend, LinearScale, PointElement, Tooltip } from "chart.js";

import { Bubble, Pie } from "react-chartjs-2";
import { Link } from "react-router-dom";
import { sway } from "sway";
import {
    bootsPalette,
    chartDimensions,
    floralPalette,
    rainbowPalette,
    SWAY_COLORS,
} from "../../../utils";
import { getBubbleChartOptions, getPieChartOptions } from "../../../utils/charts";
import { IChildChartProps } from "./BillChartsContainer";

ChartJS.register(ArcElement, LinearScale, PointElement, Tooltip, Legend);

export const PieAffinityChart: React.FC<IChildChartProps> = ({ score }) => {
    const districtScores: { [key: number]: sway.IBaseScore } = score.districts;
    if (isEmptyObject(districtScores)) {
        return (
            <>
                <p className="text-center">
                    We can't show a score because you haven't voted on any bills yet.
                </p>
                <p className="text-center">
                    Click <Link to={ROUTES.pastBills}>here</Link> to start voting!
                </p>
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
                backgroundColor: floralPalette.concat(bootsPalette).concat(rainbowPalette),
                hoverBackgroundColor: "rebeccapurple",
            },
        ],
    };

    const chartOptions = getPieChartOptions();

    return (
        <Pie
            data={data}
            width={chartDimensions()}
            height={chartDimensions()}
            options={chartOptions}
        />
    );
};

interface IBubblePoint {
    x: number;
    y: number;
    r: number;
    label: string;
}

const BubbleAffinityChart: React.FC<IChildChartProps> = ({ score, billFirestoreId }) => {
    const districtScores: { [key: number]: sway.IBaseScore } = score.districts;
    const districtKeys = Object.keys(districtScores);

    const data = {
        labels: districtKeys.map((key: string): string => {
            // NOSONAR
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
                backgroundColor: SWAY_COLORS.primaryLight,
                borderColor: SWAY_COLORS.primary,
                borderCapStyle: "butt",
                borderDash: [],
                borderDashOffset: 0.0,
                borderJoinStyle: "miter",
                pointBorderColor: SWAY_COLORS.primary,
                pointBackgroundColor: "#fff",
                pointBorderWidth: 1,
                pointHoverRadius: 5,
                pointHoverBackgroundColor: SWAY_COLORS.primary,
                pointHoverBorderColor: SWAY_COLORS.secondary,
                pointHoverBorderWidth: 2,
                pointRadius: 1,
                pointHitRadius: 10,
            },
        ],
    };

    const datasetData: number[] = data.datasets[0].data.map((item: IBubblePoint) => item.y);
    const max: number = Math.max(...datasetData) || 1;
    const min: number = Math.min(...datasetData) || -1;

    const chartOptions = getBubbleChartOptions({ min, max });

    return (
        <Bubble
            data={data}
            width={chartDimensions()}
            height={chartDimensions()}
            options={chartOptions}
            style={{ maxWidth: chartDimensions(), maxHeight: chartDimensions() }}
        />
    );
};

export default BubbleAffinityChart;
