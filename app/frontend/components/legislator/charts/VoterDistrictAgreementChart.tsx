/** @format */

import { logDev } from "app/frontend/sway_utils";
import {
    BarElement,
    CategoryScale,
    Chart as ChartJS,
    Legend,
    LinearScale,
    Title,
    Tooltip,
} from "chart.js";
import { useMemo } from "react";
import { Bar } from "react-chartjs-2";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../sway_utils";
import { getBarChartOptions } from "../../../sway_utils/charts";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const VoterDistrictAgreementChart: React.FC<{
    scores: sway.IAggregatedBillLocaleScores;
    title: string;
}> = ({ scores, title }) => {
    logDev("VoterDistrictAgreementChart.score", scores);

    const agreedScore = useMemo(() => {
        if (isFinite(scores.totalAgreedDistrict)) {
            return scores.totalAgreedDistrict;
        }
        return 0;
    }, [scores.totalAgreedDistrict]);

    const disagreedScore = useMemo(() => {
        if (isFinite(scores.totalDisagreedDistrict)) {
            return scores.totalDisagreedDistrict;
        }
        return 0;
    }, [scores.totalDisagreedDistrict]);

    const data = useMemo(
        () => ({
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
                        { x: "Agreed", y: agreedScore },
                        { x: "Disagreed", y: disagreedScore },
                    ],
                },
            ],
        }),
        [agreedScore, disagreedScore],
    );

    const max = useMemo(
        () => Math.max(...[agreedScore, disagreedScore]),
        [agreedScore, disagreedScore],
    );

    if (agreedScore === 0 && disagreedScore === 0) {
        return null;
    }

    return (
        <Bar
            width={chartDimensions()}
            height={chartDimensions()}
            data={data}
            options={getBarChartOptions({ max, title })}
            style={{ maxWidth: chartDimensions(), maxHeight: chartDimensions() }}
        />
    );
};

export default VoterDistrictAgreementChart;
