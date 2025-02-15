/** @format */

import SwayLoading from "app/frontend/components/SwayLoading";
import { isAtLargeLegislator, isEmptyObject } from "app/frontend/sway_utils";
import { useMemo, useRef, useState } from "react";
import { Button, Placeholder } from "react-bootstrap";
import { FiMap, FiStar } from "react-icons/fi";
import { isEmptyScore } from "../../../sway_utils/charts";
import VoterAgreementChart from "./VoterAgreementChart";
import { IChartContainerProps, IMobileChartChoice } from "./utils";

const LegislatorMobileChartsContainer: React.FC<IChartContainerProps> = ({
    legislator,
    userLegislatorScore,
    // localeScores,
    isLoading,
}) => {
    const ref = useRef<HTMLDivElement | null>(null);
    const [selected, setSelected] = useState<number>(0);

    const components = useMemo(() => {
        return [
            {
                Icon: FiStar,
                label: "You",
                title: `Your Sway Score with ${legislator.fullName}`,
                score: userLegislatorScore,
                Component: VoterAgreementChart,
            },
            {
                Icon: FiMap,
                label: "District",
                title: isAtLargeLegislator(legislator.district)
                    ? `Sway Scores for ${legislator.fullName}`
                    : `District ${legislator.district.number} Sway Scores for ${legislator.fullName}`,
                score: userLegislatorScore?.legislatorDistrictScore,
                Component: VoterAgreementChart,
            },
        ] as IMobileChartChoice[];
    }, [legislator.district, legislator.fullName, userLegislatorScore]);

    if (isLoading && isEmptyObject(components)) {
        return (
            <div className="col">
                <Placeholder animation="glow" size="lg" xs={12} />
            </div>
        );
    }

    return (
        <div ref={ref} className="col">
            <div className="row">
                {components.map((component: IMobileChartChoice, index: number) => {
                    const isSelected = index === selected;
                    return (
                        <div key={`chart-option-${index}`} className="col text-center">
                            <Button
                                variant={isSelected ? "primary" : "outline-primary"}
                                onClick={() => setSelected(index)}
                                className={"py-2 w-100"}
                            >
                                <div>{component.label}</div>
                                <div>
                                    <component.Icon />
                                </div>
                            </Button>
                        </div>
                    );
                })}
            </div>
            {components.map((component: IMobileChartChoice, index: number) => {
                if (index !== selected) return null;
                if (isLoading) {
                    return (
                        <div key={`display-chart-${index}`} className="mt-2">
                            <SwayLoading />
                        </div>
                    );
                }

                return (
                    <div key={index} className="col-12 text-center mt-2" style={{ height: 300 }}>
                        <component.Component
                            title={component.title}
                            scores={component.score}
                            colors={component.colors}
                            isEmptyScore={isEmptyScore(component.score)}
                        />
                    </div>
                );
            })}
        </div>
    );
};

export default LegislatorMobileChartsContainer;
