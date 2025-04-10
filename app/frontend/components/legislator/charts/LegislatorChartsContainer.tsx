/** @format */

import SwayLoading from "app/frontend/components/SwayLoading";
import { isAtLargeLegislator, isEmptyObject } from "app/frontend/sway_utils";
import { useMemo, useRef } from "react";
import { Placeholder } from "react-bootstrap";
import { isEmptyScore } from "../../../sway_utils/charts";
import VoterAgreementChart from "./VoterAgreementChart";
import { IChartChoice, IChartContainerProps } from "./utils";

const LegislatorChartsContainer: React.FC<IChartContainerProps> = ({ legislator, userLegislatorScore, isLoading }) => {
    const ref: React.Ref<HTMLDivElement | null> = useRef(null);

    const components = useMemo(() => {
        return [
            {
                title: `Your Sway Score with ${legislator.full_name}`,
                score: userLegislatorScore,
                Component: VoterAgreementChart,
            },
            !userLegislatorScore?.legislator_district_score
                ? null
                : {
                      title: isAtLargeLegislator(legislator.district)
                          ? `Sway Scores for ${legislator.full_name}`
                          : `District ${legislator.district.number} Sway Scores for ${legislator.full_name}`,
                      score: userLegislatorScore?.legislator_district_score,
                      Component: VoterAgreementChart,
                  },
        ].filter(Boolean) as IChartChoice[];
    }, [legislator.district, legislator.full_name, userLegislatorScore]);

    if (isLoading && isEmptyObject(components)) {
        return <Placeholder animation="glow" size="lg" xs={12} />;
    }

    return (
        <div ref={ref} className="row">
            {components.map((component: IChartChoice, index: number) => {
                const { score, title, colors, Component } = component;
                if (isLoading) {
                    return (
                        <div key={index} className={"col"}>
                            <SwayLoading />
                        </div>
                    );
                }
                const emptyScore = isEmptyScore(score);
                return (
                    <div key={index} className="col-12 col-md-6 text-end" style={{ height: 300 }}>
                        <Component title={title} scores={score} colors={colors} isEmptyScore={emptyScore} />
                    </div>
                );
            })}
        </div>
    );
};

export default LegislatorChartsContainer;
