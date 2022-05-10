/** @format */

import { ROUTES } from "@sway/constants";
import { isEmptyObject, isNumber } from "@sway/utils";

import { Bar } from "react-chartjs-2";
import { Link } from "react-router-dom";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../utils";
import {
    Chart as ChartJS,
    CategoryScale,
    LinearScale,
    BarElement,
    Title,
    Tooltip,
    Legend,
} from "chart.js";
import { getBarChartOptions } from "../../../utils/charts";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

interface IProps {
    scores: sway.IAggregatedBillLocaleScores | undefined;
    title: string;
    colors: {
        primary: string;
        secondary: string;
    };
}

const VoterDistrictAgreementChart: React.FC<IProps> = ({ scores, title }) => {
    if (!scores) return null;

    if (!scores || isEmptyObject(scores)) {
        return (
            <>
                <p className="text-center mt-2">Chart available after voting on bill(s).</p>
                <p className="text-center">
                    Click <Link to={ROUTES.billOfTheWeek}>here</Link> to start voting!
                </p>
            </>
        );
    }

    const agreedScore = () => {
        if (isNumber(scores.totalAgreedDistrict)) {
            return scores.totalAgreedDistrict;
        }
        return 0;
    };

    const disagreedScore = () => {
        if (isNumber(scores.totalDisagreedDistrict)) {
            return scores.totalDisagreedDistrict;
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
