/** @format */

import { BarElement, CategoryScale, Chart as ChartJS, Legend, LinearScale, Title, Tooltip } from "chart.js";
import { useMemo } from "react";
import { Bar } from "react-chartjs-2";
import { sway } from "sway";
import { SWAY_COLORS } from "../../../sway_utils";
import { getBarChartOptions } from "../../../sway_utils/charts";
import { IChartChoiceComponentProps } from "./utils";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

const VoterAgreementChart: React.FC<IChartChoiceComponentProps & { scores: sway.scoring.IAgreeable }> = ({
    scores,
    title,
    isEmptyScore,
}) => {
    const data = useMemo(
        () => ({
            labels: ["Agreed", "Disagreed", "Legislator Abstained", "No Legislator Vote"],
            datasets: [
                {
                    label: "",
                    backgroundColor: SWAY_COLORS.primarySubtle,
                    borderColor: SWAY_COLORS.primarySubtle,
                    borderWidth: 1,
                    hoverBackgroundColor: SWAY_COLORS.primary,
                    hoverBorderColor: SWAY_COLORS.primary,
                    barPercentage: 0.8,
                    categoryPercentage: 0.8,
                    data: [
                        { x: "Agreed", y: scores.count_agreed || 0 },
                        { x: "Disagreed", y: scores.count_disagreed || 0 },
                        {
                            x: "Legislator Abstained",
                            y: scores.count_legislator_abstained || 0,
                        },
                        {
                            x: "No Legislator Vote",
                            y: scores.count_no_legislator_vote || 0,
                        },
                    ],
                },
            ],
        }),
        [
            scores.count_agreed,
            scores.count_disagreed,
            scores.count_legislator_abstained,
            scores.count_no_legislator_vote,
        ],
    );

    const max: number = useMemo(
        () =>
            Math.max(
                ...[
                    scores.count_agreed || 0,
                    scores.count_disagreed || 0,
                    scores.count_legislator_abstained || 0,
                    scores.count_no_legislator_vote || 0,
                ],
            ),
        [
            scores.count_agreed,
            scores.count_disagreed,
            scores.count_legislator_abstained,
            scores.count_no_legislator_vote,
        ],
    );

    if (isEmptyScore) {
        return null;
    }

    return (
        <Bar
            width={"100%"}
            height={"100%"}
            data={data}
            options={getBarChartOptions({ max, title })}
            style={{ width: "100%", height: "100%" }}
        />
    );
};

export default VoterAgreementChart;
