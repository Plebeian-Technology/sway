/** @format */

import { ROUTES } from "@sway/constants";
import { isNumber } from "@sway/utils";

import {
    BarElement,
    CategoryScale,
    Chart as ChartJS,
    Legend,
    LinearScale,
    Title,
    Tooltip,
} from "chart.js";
import { Bar } from "react-chartjs-2";
import { Link } from "react-router-dom";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../utils";
import { getBarChartOptions } from "../../../utils/charts";
import { IChartChoiceComponentProps } from "./utils";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const VoterDistrictAgreementChart: React.FC<IChartChoiceComponentProps> = ({
    scores,
    title,
    isEmptyScore,
}) => {
    if (isEmptyScore) {
        return (
            <>
                <p className="text-center mt-1">Chart available after voting on bill(s).</p>
                <p className="text-center">
                    Click <Link to={ROUTES.billOfTheWeek}>here</Link> to start voting!
                </p>
            </>
        );
    }

    const score = scores as sway.IAggregatedBillLocaleScores;
    const agreedScore = () => {
        if (isNumber(score.totalAgreedDistrict)) {
            return score.totalAgreedDistrict;
        }
        return 0;
    };

    const disagreedScore = () => {
        if (isNumber(score.totalDisagreedDistrict)) {
            return score.totalDisagreedDistrict;
        }
        return 0;
    };

    if (agreedScore() === 0 && disagreedScore() === 0) {
        return null;
    }

    const data = {
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
                    { x: "Agreed", y: agreedScore() },
                    { x: "Disagreed", y: disagreedScore() },
                ],
            },
        ],
    };

    const max: number = Math.max(...[agreedScore(), disagreedScore()]);
    const chartOptions = getBarChartOptions({ max, title });

    return (
        <Bar
            width={chartDimensions()}
            height={chartDimensions()}
            data={data}
            options={chartOptions}
        />
    );
};

export default VoterDistrictAgreementChart;
