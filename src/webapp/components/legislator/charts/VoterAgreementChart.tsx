/** @format */

import { Typography } from "@mui/material";
import { ROUTES } from "src/constants";
import { isEmptyObject } from "src/utils";
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

ChartJS.register(
    CategoryScale,
    LinearScale,
    BarElement,
    Title,
    Tooltip,
    Legend,
);

interface IProps {
    scores: sway.IUserLegislatorScoreV2 | undefined;
    title: string;
    colors: {
        primary: string;
        secondary: string;
    };
}

const VoterAgreementChart: React.FC<IProps> = ({ scores, title, colors }) => {
    if (
        !scores ||
        isEmptyObject(scores) ||
        Object.values(scores).every((s) => s === 0)
    ) {
        return (
            <>
                <Typography
                    style={{ textAlign: "center", marginTop: 5 }}
                    variant="body1"
                    color="textPrimary"
                    component="p"
                >
                    {"Chart available after voting on bill(s)."}
                </Typography>
                <Typography
                    style={{ textAlign: "center" }}
                    variant="body2"
                    color="textSecondary"
                    component="p"
                >
                    Click <Link to={ROUTES.billOfTheWeek}>here</Link> to start
                    voting!
                </Typography>
            </>
        );
    }

    const data = {
        labels: [
            "Agreed",
            "Disagreed",
            "Legislator Abstained",
            "No Legislator Vote",
        ],
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
                    { x: "Agreed", y: scores.countAgreed || 0 },
                    { x: "Disagreed", y: scores.countDisagreed || 0 },
                    {
                        x: "Legislator Abstained",
                        y: scores.countLegislatorAbstained || 0,
                    },
                    {
                        x: "No Legislator Vote",
                        y: scores.countNoLegislatorVote || 0,
                    },
                ],
            },
        ],
    };

    const max: number = Math.max(
        ...[
            scores.countAgreed || 0,
            scores.countDisagreed || 0,
            scores.countLegislatorAbstained || 0,
            scores.countNoLegislatorVote || 0,
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