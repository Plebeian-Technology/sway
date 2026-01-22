/** @format */

import { BarChart } from "@mui/x-charts/BarChart";
import { chartDimensions, isEmptyObject, SWAY_COLORS } from "../../../sway_utils";
import { IChildChartProps } from "./BillChartsContainer";

const DistrictVotesChart: React.FC<IChildChartProps> = ({ bill, score, district }) => {
    const districtScore = score.districts.find((d) => d.district.name === district.name);

    if (isEmptyObject(districtScore)) {
        console.warn(
            `DistrictVoteChart.districtScore is empty for bill.id = ${bill.id}, district.id = ${district.id}. Render null component.`,
        );
        return null;
    }

    const dimensions = chartDimensions();

    return (
        <div style={{ maxWidth: dimensions, maxHeight: dimensions, margin: "auto" }}>
            <BarChart
                width={dimensions}
                height={dimensions}
                xAxis={[{ scaleType: "band", data: ["Support", "Oppose"] }]}
                series={[
                    {
                        data: [districtScore?.for || 0, districtScore?.against || 0],
                        color: SWAY_COLORS.primarySubtle,
                        label: `Votes Cast in District ${district.number} on ${bill.title}`,
                    },
                ]}
            />
        </div>
    );
};

export default DistrictVotesChart;
