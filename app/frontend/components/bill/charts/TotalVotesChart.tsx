/** @format */

import { isCongressLocale, titleize } from "app/frontend/sway_utils";
import { BarElement, CategoryScale, Chart as ChartJS, Legend, LinearScale, Title, Tooltip } from "chart.js";

import { useLocale } from "app/frontend/hooks/useLocales";
import { Bar } from "react-chartjs-2";
import { chartDimensions, SWAY_COLORS } from "../../../sway_utils";
import { getBarChartOptions } from "../../../sway_utils/charts";
import { IChildChartProps } from "./BillChartsContainer";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const TotalVotesChart: React.FC<IChildChartProps> = ({ bill, score, district: _district }) => {
    const [locale] = useLocale();

    const location = isCongressLocale(locale) ? "the United States" : titleize(locale.city);
    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: `All Votes Cast in ${location} on ${bill.title}`,
                backgroundColor: SWAY_COLORS.primarySubtle,
                borderColor: SWAY_COLORS.primarySubtle,
                borderWidth: 1,
                hoverBackgroundColor: SWAY_COLORS.primary,
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

    const max: number = Math.max(...[Number(score.for || 0), Number(score.against || 0)]);
    const chartOptions = getBarChartOptions({ max });
    const dimensions = chartDimensions();

    return (
        <Bar
            width={dimensions}
            height={dimensions}
            data={data}
            options={chartOptions}
            style={{ maxWidth: dimensions, maxHeight: dimensions, margin: "auto" }}
        />
    );
};

export default TotalVotesChart;
