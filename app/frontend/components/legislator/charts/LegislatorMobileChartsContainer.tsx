/** @format */

import { getNumericDistrict, isAtLargeLegislator, isEmptyObject, titleize } from "app/frontend/sway_utils";
import { useCallback, useMemo, useRef, useState } from "react";
import { FiMap, FiStar } from "react-icons/fi";
import { Animate } from "react-simple-animate";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { swayBlue, SWAY_COLORS } from "../../../sway_utils";
import { isEmptyScore } from "../../../sway_utils/charts";
import CenteredLoading from "../../dialogs/CenteredLoading";
import DialogWrapper from "../../dialogs/DialogWrapper";
import { IChartContainerProps, IMobileChartChoice } from "./utils";
import VoterAgreementChart from "./VoterAgreementChart";
import VoterDistrictAgreementChart from "./VoterDistrictAgreementChart";

const LegislatorMobileChartsContainer: React.FC<IChartContainerProps> = ({
    legislator,
    userLegislatorScore,
    localeScores,
    isLoading,
}) => {
    const ref = useRef<HTMLDivElement | null>(null);
    const [open, setOpen] = useOpenCloseElement(ref);

    const [selected, setSelected] = useState<number>(0);
    const [expanded, setExpanded] = useState<boolean>(false);

    const handleSetExpanded = useCallback(() => {
        setOpen(true);
        setExpanded(true);
    }, [setOpen]);

    const handleClose = useCallback(() => {
        setOpen(false);
        setExpanded(false);
    }, [setOpen]);

    const components = useMemo(() => {
        return [
            {
                Icon: FiStar,
                label: "You",
                title: `Your Sway Score with ${legislator.full_name}`,
                score: userLegislatorScore,
                Component: VoterAgreementChart,
                colors: {
                    primary: SWAY_COLORS.primary,
                    secondary: SWAY_COLORS.primaryLight,
                },
            },
            {
                Icon: FiMap,
                label: "District",
                title: isAtLargeLegislator({
                    district: legislator.district,
                    regionCode: legislator.regionCode,
                })
                    ? `${titleize(legislator.city)} Sway Scores for ${legislator.full_name}`
                    : `District ${getNumericDistrict(legislator.district)} Sway Scores for ${
                          legislator.full_name
                      }`,
                score: localeScores,
                Component: VoterDistrictAgreementChart,
                colors: {
                    primary: SWAY_COLORS.primary,
                    secondary: SWAY_COLORS.primaryLight,
                },
            },
        ] as IMobileChartChoice[];
    }, [
        userLegislatorScore,
        localeScores,
        legislator.district,
        legislator.regionCode,
        legislator.full_name,
        legislator.city,
    ]);

    const selectedChart = expanded && components[selected];

    if (isLoading && isEmptyObject(components)) {
        return (
            <div className="col">
                <CenteredLoading message="Loading Charts..." />
            </div>
        );
    }

    return (
        <Animate play={!isLoading} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div ref={ref} className="col">
                <div className="row">
                    {components.map((component: IMobileChartChoice, index: number) => {
                        const isSelected = index === selected;
                        return (
                            <div
                                key={`chart-option-${index}`}
                                onClick={() => setSelected(index)}
                                className={`col text-center border border-2 rounded mx-2 py-2 ${
                                    isSelected ? "border-primary blue" : ""
                                }`}
                            >
                                <div>{component.label}</div>
                                <div>
                                    <component.Icon
                                        style={{
                                            color: index === selected ? swayBlue : "initial",
                                        }}
                                    />
                                </div>
                            </div>
                        );
                    })}
                </div>
                {components.map((component: IMobileChartChoice, index: number) => {
                    if (index !== selected) return null;
                    if (isLoading) {
                        return (
                            <div key={`display-chart-${index}`} className="mt-2">
                                <CenteredLoading
                                    message={`Loading ${titleize(component.title)} Chart...`}
                                />
                            </div>
                        );
                    }

                    return (
                        <div
                            key={`display-chart-${index}`}
                            className="col"
                            onClick={handleSetExpanded}
                        >
                            <component.Component
                                title={component.title}
                                scores={component.score}
                                colors={component.colors}
                                isEmptyScore={isEmptyScore(component.score)}
                            />
                        </div>
                    );
                })}
                {selectedChart && (
                    <DialogWrapper open={open} setOpen={handleClose}>
                        <selectedChart.Component
                            title={selectedChart.title}
                            scores={selectedChart.score}
                            colors={selectedChart.colors}
                            isEmptyScore={false}
                        />
                    </DialogWrapper>
                )}
            </div>
        </Animate>
    );
};

export default LegislatorMobileChartsContainer;
