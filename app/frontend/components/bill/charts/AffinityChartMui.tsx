/** @format */

import { PieChart } from "@mui/x-charts/PieChart";
import { ScatterChart } from "@mui/x-charts/ScatterChart";
import { isEmptyObject } from "app/frontend/sway_utils";

import { sway } from "sway";
import { bootsPalette, chartDimensions, floralPalette, rainbowPalette, SWAY_COLORS } from "../../../sway_utils";
import { IChildChartProps } from "./BillChartsContainer";

export const PieAffinityChartMui: React.FC<IChildChartProps> = ({ score }) => {
    const districtScores: { [key: number]: sway.IBaseScore } = score.districts;
    if (isEmptyObject(districtScores)) {
        return (
            <>
                <p className="text-center">We can't show a score because you haven't voted on any bills yet.</p>
                <p className="text-center">Click here to start voting!</p>
            </>
        );
    }

    const districtKeys = Object.keys(districtScores);
    const palette = floralPalette.concat(bootsPalette).concat(rainbowPalette);

    const seriesData = districtKeys
        .map((key: string, index: number) => {
            const dscore: sway.IBaseScore = districtScores[Number(key)];
            const amount = Number(dscore.for) - Number(dscore.against);
            const symbol = amount > 0 ? "+" : "";
            return {
                id: key,
                value: Math.abs(amount), // Ensure positive for pie slice size
                label: `D-${key} (${symbol}${amount})`,
                color: palette[index % palette.length],
            };
        })
        .filter((d) => d.value > 0); // Pie slices must have size > 0

    const dimensions = chartDimensions();

    return (
        <PieChart
            series={[
                {
                    data: seriesData,
                    innerRadius: 0,
                    outerRadius: dimensions / 2 - 20,
                    paddingAngle: 0,
                    cornerRadius: 0,
                },
            ]}
            width={dimensions}
            height={dimensions}
        />
    );
};

export const BubbleAffinityChartMui: React.FC<IChildChartProps> = ({ score }) => {
    const districtScores: { [key: number]: sway.IBaseScore } = score.districts;
    const districtKeys = Object.keys(districtScores);

    const data = districtKeys
        .map((key: string) => {
            const dscore: sway.IBaseScore = districtScores[Number(key)];
            return {
                x: Number(key),
                y: Number(dscore.for) - Number(dscore.against),
                id: key,
            };
        })
        .filter((item) => Number(item.id) !== 0); // Hide key 0 as per original r=0 logic

    const dimensions = chartDimensions();

    return (
        <div style={{ maxWidth: dimensions, maxHeight: dimensions }}>
            <ScatterChart
                width={dimensions}
                height={dimensions}
                series={[
                    {
                        label: "Affinity to bill By District",
                        data: data,
                        color: SWAY_COLORS.primary,
                    },
                ]}
                xAxis={[{ label: "District" }]}
                yAxis={[{ label: "Affinity" }]}
            />
        </div>
    );
};

export default BubbleAffinityChartMui;
