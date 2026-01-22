/** @format */

import { BarChart } from "@mui/x-charts/BarChart";
import { logDev } from "app/frontend/sway_utils";
import { useMemo } from "react";
import { sway } from "sway";
import { chartDimensions, SWAY_COLORS } from "../../../sway_utils";

const VoterDistrictAgreementChart: React.FC<{
    scores: sway.scoring.ILegislatorDistrictScore;
    title: string;
}> = ({ scores, title }) => {
    logDev("VoterDistrictAgreementChart.score", scores);

    const agreedScore = useMemo(() => {
        if (isFinite(scores.count_agreed)) {
            return scores.count_agreed;
        }
        return 0;
    }, [scores.count_agreed]);

    const disagreedScore = useMemo(() => {
        if (isFinite(scores.count_disagreed)) {
            return scores.count_disagreed;
        }
        return 0;
    }, [scores.count_disagreed]);

    if (agreedScore === 0 && disagreedScore === 0) {
        return null;
    }

    const dimensions = chartDimensions();

    return (
        <div style={{ maxWidth: dimensions, maxHeight: dimensions, display: "flex", flexDirection: "column", alignItems: "center" }}>
            {title && (
                <div style={{ marginBottom: 5, fontFamily: "sans-serif", fontSize: 14, color: "#666", fontWeight: "bold" }}>
                    {title}
                </div>
            )}
            <BarChart
                width={dimensions}
                height={dimensions}
                xAxis={[{ scaleType: "band", data: ["Agreed", "Disagreed"] }]}
                series={[
                    {
                        data: [agreedScore, disagreedScore],
                        color: SWAY_COLORS.primaryLight,
                    },
                ]}
            />
        </div>
    );
};

export default VoterDistrictAgreementChart;
