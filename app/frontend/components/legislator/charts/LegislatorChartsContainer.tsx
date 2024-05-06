/** @format */

import { isEmptyObject, titleize } from "app/frontend/sway_utils";
import { useCallback, useMemo, useRef, useState } from "react";
import { Animate } from "react-simple-animate";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { SWAY_COLORS } from "../../../sway_utils";
import { isEmptyScore } from "../../../sway_utils/charts";
import SwaySpinner from "../../SwaySpinner";
import DialogWrapper from "../../dialogs/DialogWrapper";
import VoterAgreementChart from "./VoterAgreementChart";
import { IChartChoice, IChartContainerProps } from "./utils";

const LegislatorChartsContainer: React.FC<IChartContainerProps> = ({
    legislator,
    userLegislatorScore,
    isLoading,
}) => {
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
                colors: {
                    primary: SWAY_COLORS.primary,
                    secondary: SWAY_COLORS.primaryLight,
                },
            },
            // {
            //     title: isAtLargeLegislator(legislator.district)
            //         ? `Sway Scores for ${legislator.fullName}`
            //         : `District ${legislator.district.number} Sway Scores for ${
            //               legislator.fullName
            //           }`,
            //     score: localeScores,
            //     Component: VoterDistrictAgreementChart,
            //     colors: {
            //         primary: SWAY_COLORS.primary,
            //         secondary: SWAY_COLORS.primaryLight,
            //     },
            // },
        ] as IChartChoice[];
    }, [legislator.fullName, userLegislatorScore]);

    const selectedChart = useMemo(
        () => selected > -1 && components[selected],
        [selected, components],
    );

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
                                <SwaySpinner
                                    message={`Loading ${titleize(component.title)} Chart...`}
                                />
                            </div>
                        );
                    }
                    const emptyScore = isEmptyScore(score);
                    return (
                        <div
                            key={index}
                            onClick={emptyScore ? undefined : () => handleSetSelected(index)}
                            className={
                                "d-flex col-12 col-md-6 align-items-center justify-content-center pointer"
                            }
                        >
                            <Component
                                title={title}
                                scores={score}
                                colors={colors}
                                isEmptyScore={emptyScore}
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

export default LegislatorChartsContainer;
