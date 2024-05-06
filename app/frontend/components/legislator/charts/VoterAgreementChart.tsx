/** @format */

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
import { chartDimensions } from "../../../sway_utils";
import { getBarChartOptions } from "../../../sway_utils/charts";
import { IChartChoiceComponentProps } from "./utils";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const VoterAgreementChart: React.FC<
    IChartChoiceComponentProps & { scores: sway.scoring.IAgreeable }
> = ({ scores, title, colors, isEmptyScore }) => {
    const data = useMemo(
        () => ({
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
        }),
        [
            colors.primary,
            colors.secondary,
            scores.countAgreed,
            scores.countDisagreed,
            scores.countLegislatorAbstained,
            scores.countNoLegislatorVote,
        ],
    );

    const max: number = useMemo(
        () =>
            Math.max(
                ...[
                    scores.countAgreed || 0,
                    scores.countDisagreed || 0,
                    scores.countLegislatorAbstained || 0,
                    scores.countNoLegislatorVote || 0,
                ],
            ),
        [
            scores.countAgreed,
            scores.countDisagreed,
            scores.countLegislatorAbstained,
            scores.countNoLegislatorVote,
        ],
    );

    if (isEmptyScore) {
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

export default VoterAgreementChart;
