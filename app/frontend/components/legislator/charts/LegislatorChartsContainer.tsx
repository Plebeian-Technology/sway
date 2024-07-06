/** @format */

import SuspenseFullScreen from "app/frontend/components/dialogs/SuspenseFullScreen";
import { isAtLargeLegislator, isEmptyObject, titleize } from "app/frontend/sway_utils";
import { lazy, useCallback, useMemo, useRef, useState } from "react";
import { Animate } from "react-simple-animate";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { isEmptyScore } from "../../../sway_utils/charts";
import SwaySpinner from "../../SwaySpinner";
import VoterAgreementChart from "./VoterAgreementChart";
import { IChartChoice, IChartContainerProps } from "./utils";

const DialogWrapper = lazy(() => import("../../dialogs/DialogWrapper"));

const LegislatorChartsContainer: React.FC<IChartContainerProps> = ({ legislator, userLegislatorScore, isLoading }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(-1);

    const handleSetSelected = useCallback(
        (index: number) => {
            setOpen(true);
            setSelected(index);
        },
        [setOpen],
    );

    const handleClose = useCallback(() => {
        setOpen(false);
        setSelected(-1);
    }, [setOpen]);

    const components = useMemo(() => {
        return [
            {
                title: `Your Sway Score with ${legislator.fullName}`,
                score: userLegislatorScore,
                Component: VoterAgreementChart,
            },
            {
                title: isAtLargeLegislator(legislator.district)
                    ? `Sway Scores for ${legislator.fullName}`
                    : `District ${legislator.district.number} Sway Scores for ${legislator.fullName}`,
                score: userLegislatorScore?.legislatorDistrictScore,
                Component: VoterAgreementChart,
            },
        ] as IChartChoice[];
    }, [legislator.district, legislator.fullName, userLegislatorScore]);

    const selectedChart = useMemo(() => selected > -1 && components[selected], [selected, components]);

    if (isLoading && isEmptyObject(components)) {
        return <SwaySpinner message="Loading Legislator Charts..." />;
    }

    return (
        <Animate play={!isLoading} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div ref={ref} className="row">
                {components.map((component: IChartChoice, index: number) => {
                    const { score, title, colors, Component } = component;
                    if (isLoading) {
                        return (
                            <div key={index} className={"col"}>
                                <SwaySpinner message={`Loading ${titleize(component.title)} Chart...`} />
                            </div>
                        );
                    }
                    const emptyScore = isEmptyScore(score);
                    return (
                        <div
                            key={index}
                            onClick={emptyScore ? undefined : () => handleSetSelected(index)}
                            className={"d-flex col-12 col-md-6 align-items-center justify-content-center pointer"}
                        >
                            <Component title={title} scores={score} colors={colors} isEmptyScore={emptyScore} />
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

export default LegislatorChartsContainer;
