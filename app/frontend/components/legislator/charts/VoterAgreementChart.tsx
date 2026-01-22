/** @format */

import { BarChart } from "@mui/x-charts/BarChart";
import { sway } from "sway";
import { SWAY_COLORS } from "../../../sway_utils";
import { IChartChoiceComponentProps } from "./utils";

const VoterAgreementChart: React.FC<IChartChoiceComponentProps & { scores: sway.scoring.IAgreeable }> = ({
    scores,
    title,
    isEmptyScore,
}) => {
    if (isEmptyScore) {
        return null;
    }

    return (
        <div style={{ width: "100%", height: "100%", minHeight: 300, display: "flex", flexDirection: "column" }}>
            {title && (
                <div
                    style={{
                        textAlign: "center",
                        marginBottom: 5,
                        fontFamily: "sans-serif",
                        fontSize: 14,
                        color: "#666",
                        fontWeight: "bold",
                    }}
                >
                    {title}
                </div>
            )}
            <div style={{ flex: 1, minHeight: 0, width: "100%" }}>
                <BarChart
                    xAxis={[
                        {
                            scaleType: "band",
                            data: ["Agreed", "Disagreed", "Legislator Abstained", "No Legislator Vote"],
                        },
                    ]}
                    series={[
                        {
                            data: [
                                scores.count_agreed || 0,
                                scores.count_disagreed || 0,
                                scores.count_legislator_abstained || 0,
                                scores.count_no_legislator_vote || 0,
                            ],
                            color: SWAY_COLORS.primarySubtle,
                        },
                    ]}
                    margin={{ top: 10, right: 10, bottom: 30, left: 40 }}
                />
            </div>
        </div>
    );
};

export default VoterAgreementChart;
