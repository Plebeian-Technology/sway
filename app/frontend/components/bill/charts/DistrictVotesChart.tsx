/** @format */


import { Bar } from "react-chartjs-2";
import { chartDimensions, logDev, SWAY_COLORS } from "../../../sway_utils";
import { IChildChartProps } from "./BillChartsContainer";

import { BarElement, CategoryScale, Chart as ChartJS, Legend, LinearScale, Title, Tooltip } from "chart.js";
import { isEmpty } from "lodash";
import { getBarChartOptions } from "../../../sway_utils/charts";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const DistrictVotesChart: React.FC<IChildChartProps> = ({ bill, score, district }) => {
    logDev("DistrictVotesChart", { bill, score, district })
    const districtScore = score.districts.find(d => d.district.name === district.name);

    if (isEmpty(districtScore)) {
        return null;
    }

    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: `Votes Cast in District ${district.number} on ${bill.title}`,
                backgroundColor: district.number ? SWAY_COLORS.primaryLight : SWAY_COLORS.primary,
                borderColor: SWAY_COLORS.primary,
                borderWidth: 1,
                hoverBackgroundColor: district.number ? SWAY_COLORS.primaryLight : SWAY_COLORS.primary,
                hoverBorderColor: SWAY_COLORS.primary,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Support", y: districtScore?.for || 0 },
                    { x: "Oppose", y: districtScore?.against || 0 },
                ],
            },
        ],
    };

    const max: number = Math.max(...[Number(districtScore?.for || 0), Number(districtScore?.against || 0)]);
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

export default DistrictVotesChart;
