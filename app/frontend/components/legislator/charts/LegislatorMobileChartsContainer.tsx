/** @format */

import SuspenseFullScreen from "app/frontend/components/dialogs/SuspenseFullScreen";
import { isAtLargeLegislator, isEmptyObject, titleize } from "app/frontend/sway_utils";
import { lazy, useCallback, useMemo, useRef, useState } from "react";
import { Button } from "react-bootstrap";
import { FiMap, FiStar } from "react-icons/fi";
import { Animate } from "react-simple-animate";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { isEmptyScore } from "../../../sway_utils/charts";
import CenteredLoading from "../../dialogs/CenteredLoading";
import VoterAgreementChart from "./VoterAgreementChart";
import { IChartContainerProps, IMobileChartChoice } from "./utils";

const DialogWrapper = lazy(() => import("../../dialogs/DialogWrapper"));

const LegislatorMobileChartsContainer: React.FC<IChartContainerProps> = ({
    legislator,
    userLegislatorScore,
    // localeScores,
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
                                <CenteredLoading message={`Loading ${titleize(component.title)} Chart...`} />
                            </div>
                        );
                    }

                    return (
                        <div key={`display-chart-${index}`} className="col" onClick={handleSetExpanded}>
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
                    <SuspenseFullScreen>
                        <DialogWrapper open={open} setOpen={handleClose}>
                            <selectedChart.Component
                                title={selectedChart.title}
                                scores={selectedChart.score}
                                colors={selectedChart.colors}
                                isEmptyScore={false}
                            />
                        </DialogWrapper>
                    </SuspenseFullScreen>
                )}
            </div>
        </Animate>
    );
};

export default LegislatorMobileChartsContainer;
