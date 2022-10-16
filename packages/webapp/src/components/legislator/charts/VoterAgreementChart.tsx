/** @format */

import { ROUTES } from "@sway/constants";
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
import { chartDimensions } from "../../../utils";
import { getBarChartOptions } from "../../../utils/charts";
import { IChartChoiceComponentProps } from "./utils";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const VoterAgreementChart: React.FC<IChartChoiceComponentProps> = ({
    scores,
    title,
    colors,
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

    const score = scores as sway.IUserLegislatorScoreV2;
    const data = {
        labels: ["Agreed", "Disagreed", "Legislator Abstained", "No Legislator Vote"],
        datasets: [
            {
                label: "",
                backgroundColor: colors.primary,
                borderColor: colors.secondary,
                borderWidth: 1,
                hoverBackgroundColor: colors.primary,
                hoverBorderColor: colors.secondary,
                barPercentage: 0.8,
                categoryPercentage: 0.8,
                data: [
                    { x: "Agreed", y: score.countAgreed || 0 },
                    { x: "Disagreed", y: score.countDisagreed || 0 },
                    {
                        x: "Legislator Abstained",
                        y: score.countLegislatorAbstained || 0,
                    },
                    {
                        x: "No Legislator Vote",
                        y: score.countNoLegislatorVote || 0,
                    },
                ],
            },
        ],
    };

    const max: number = Math.max(
        ...[
            score.countAgreed || 0,
            score.countDisagreed || 0,
            score.countLegislatorAbstained || 0,
            score.countNoLegislatorVote || 0,
        ],
    );
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

export default VoterAgreementChart;
