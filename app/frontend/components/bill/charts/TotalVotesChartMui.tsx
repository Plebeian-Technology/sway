/** @format */

import { BarChart } from "@mui/x-charts/BarChart";
import { useLocale } from "app/frontend/hooks/useLocales";
import { isCongressLocale, titleize } from "app/frontend/sway_utils";
import { chartDimensions, SWAY_COLORS } from "../../../sway_utils";
import { IChildChartProps } from "./BillChartsContainer";

const TotalVotesChartMui: React.FC<IChildChartProps> = ({ bill, score, district: _district }) => {
    const [locale] = useLocale();

    const location = isCongressLocale(locale) ? "the United States" : titleize(locale.city);
    const dimensions = chartDimensions();

    return (
        <div style={{ maxWidth: dimensions, maxHeight: dimensions, margin: "auto" }}>
            <BarChart
                width={dimensions}
                height={dimensions}
                xAxis={[{ scaleType: "band", data: ["Support", "Oppose"] }]}
                series={[
                    {
                        data: [score.for || 0, score.against || 0],
                        color: SWAY_COLORS.primarySubtle,
                        label: `All Votes Cast in ${location} on ${bill.title}`,
                    },
                ]}
            />
        </div>
    );
};

export default TotalVotesChartMui;
