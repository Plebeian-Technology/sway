/** @format */

import { isCongressLocale, titleize } from "app/frontend/sway_utils";
import { BarElement, CategoryScale, Chart as ChartJS, Legend, LinearScale, Title, Tooltip } from "chart.js";

import { useLocale } from "app/frontend/hooks/useLocales";
import { Bar } from "react-chartjs-2";
import { chartDimensions, SWAY_COLORS } from "../../../sway_utils";
import { getBarChartOptions } from "../../../sway_utils/charts";
import { IChildChartProps } from "./BillChartsContainer";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const TotalVotesChart: React.FC<IChildChartProps> = ({ bill, score }) => {
    const [locale] = useLocale();

    const location = isCongressLocale(locale) ? "the United States" : titleize(locale.city);
    const data = {
        labels: ["Support", "Oppose"],
        datasets: [
            {
                label: `All Votes Cast in ${location} on ${bill.title}`,
                backgroundColor: isCongressLocale(locale) ? SWAY_COLORS.primaryLight : SWAY_COLORS.primary,
                borderColor: SWAY_COLORS.primary,
                borderWidth: 1,
                hoverBackgroundColor: isCongressLocale(locale) ? SWAY_COLORS.primaryLight : SWAY_COLORS.primary,
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

export default TotalVotesChart;
