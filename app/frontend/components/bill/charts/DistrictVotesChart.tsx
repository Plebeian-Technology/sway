/** @format */

import { STATE_CODES_NAMES } from "@sway/constants";
import { getNumericDistrict, isEmptyObject, isNumber } from "@sway/utils";

import { Bar } from "react-chartjs-2";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../utils";
import { IChildChartProps } from "./BillChartsContainer";

import {
    BarElement,
    CategoryScale,
    Chart as ChartJS,
    Legend,
    LinearScale,
    Title,
    Tooltip,
} from "chart.js";
import { getBarChartOptions } from "../../../utils/charts";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const DistrictVoteChart: React.FC<IChildChartProps> = ({ score, billFirestoreId, userLocale }) => {
    const district: string = userLocale.district;
    const numericDistrict = getNumericDistrict(district);
    const districtScore: sway.IBaseScore = score.districts[district];

    if (isEmptyObject(districtScore)) {
        return null;
    }

    const getLabel = () => {
        if (isNumber(numericDistrict)) {
            return `Votes Cast in District ${numericDistrict} on ${billFirestoreId}`;
        }
        return `Votes Cast in ${STATE_CODES_NAMES[district]} on ${billFirestoreId}`;
    };

    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: getLabel(),
                backgroundColor: numericDistrict ? SWAY_COLORS.primaryLight : SWAY_COLORS.primary,
                borderColor: SWAY_COLORS.primary,
                borderWidth: 1,
                hoverBackgroundColor: numericDistrict
                    ? SWAY_COLORS.primaryLight
                    : SWAY_COLORS.primary,
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
    const chartOptions = getBarChartOptions({ max });

    return (
        <Bar
            width={chartDimensions()}
            height={chartDimensions()}
            data={data}
            options={chartOptions}
            style={{ maxWidth: chartDimensions(), maxHeight: chartDimensions() }}
        />
    );
};

export default DistrictVoteChart;
