/** @format */

import {
    getNumericDistrict,
    isAtLargeLegislator,
    isEmptyObject,
    logDev,
    titleize,
} from "@sway/utils";
import { useMemo, useRef, useState } from "react";
import { FiMap, FiStar } from "react-icons/fi";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { swayBlue, SWAY_COLORS } from "../../../utils";
import CenteredLoading from "../../dialogs/CenteredLoading";
import DialogWrapper from "../../dialogs/DialogWrapper";
import VoterAgreementChart from "./VoterAgreementChart";
import VoterDistrictAgreementChart from "./VoterDistrictAgreementChart";

interface IProps {
    user: sway.IUser | undefined;
    legislator: sway.ILegislator;
    userLegislatorScore: sway.IUserLegislatorScoreV2 | null | undefined;
    localeScores: sway.IAggregatedBillLocaleScores | null | undefined;
    isLoading: boolean;
}

interface IChartChoice {
    title: string;
    label: string;
    score: sway.IUserLegislatorScoreV2;
    Icon: React.FC<any>;
    Component: React.FC<{
        scores: sway.IUserLegislatorScoreV2 | sway.IAggregatedBillLocaleScores;
        title: string;
        colors: {
            primary: string;
            secondary: string;
        };
    }>;
    colors: {
        primary: string;
        secondary: string;
    };
}

const LegislatorMobileChartsContainer: React.FC<IProps> = ({
    legislator,
    userLegislatorScore,
    localeScores,
    isLoading,
}) => {
    logDev("LegislatorMobileChartsContainer");
    const ref = useRef<HTMLDivElement | null>(null);
    const [open, setOpen] = useOpenCloseElement(ref);

    const [selected, setSelected] = useState<number>(0);
    const [expanded, setExpanded] = useState<boolean>(false);

    const handleSetExpanded = () => {
        setOpen(true);
        setExpanded(true);
    };
    const handleClose = () => {
        setOpen(false);
        setExpanded(false);
    };

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
                title: isAtLargeLegislator(legislator)
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
        ].filter((item) => item.score) as IChartChoice[];
    }, [userLegislatorScore, localeScores]);

    const selectedChart = expanded && components[selected];

    if (isLoading && isEmptyObject(components)) {
        return (
            <div className={"col"}>
                <CenteredLoading message="Loading Charts..." />
            </div>
        );
    }

    return (
        <div ref={ref} className="col">
            <div className="row">
                {components.map((component: IChartChoice, index: number) => {
                    const isSelected = index === selected;
                    return (
                        <div
                            key={index}
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
            {components.map((component: IChartChoice, index: number) => {
                if (index !== selected) return null;
                if (isLoading) {
                    return (
                        <div key={index}>
                            <CenteredLoading message="Loading Charts..." />
                        </div>
                    );
                }

                return isEmptyObject(component.score) ? null : (
                    <div key={index} className={"col"} onClick={handleSetExpanded}>
                        <component.Component
                            title={component.title}
                            scores={component.score}
                            colors={component.colors}
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
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default LegislatorMobileChartsContainer;
