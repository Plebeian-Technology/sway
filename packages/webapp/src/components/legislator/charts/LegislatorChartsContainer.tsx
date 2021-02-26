/** @format */

import { CircularProgress } from "@material-ui/core";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { isEmptyObject } from "@sway/utils";
import DialogWrapper from "../../dialogs/DialogWrapper";
import VoterAgreementChart from "./VoterAgreementChart";
import { SWAY_COLORS } from "../../../utils";

interface IProps {
    user: sway.IUser | undefined;
    legislator: sway.ILegislator;
    userLegislatorScore: sway.IUserLegislatorScore | undefined;
    districtScores: sway.IUserLegislatorScore | undefined;
    isLoading: boolean;
}

interface IChartChoice {
    title: string;
    score: sway.IUserLegislatorScore;
    Component: React.FC<{
        scores: sway.IUserLegislatorScore;
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

const LegislatorChartsContainer: React.FC<IProps> = ({
    legislator,
    userLegislatorScore,
    districtScores,
    isLoading,
}) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(-1);

    const handleSetSelected = (index: number) => {
        setOpen(true);
        setSelected(index);
    };
    const handleClose = () => {
        setOpen(false);
        setSelected(-1);
    };

    const components = [
        {
            title: `Your Sway Score with ${legislator.full_name}`,
            score: userLegislatorScore,
            Component: VoterAgreementChart,
            colors: {
                primary: SWAY_COLORS.primary,
                secondary: SWAY_COLORS.primaryLight,
            },
        },
        {
            title: `District ${legislator.district} Sway Scores for ${legislator.full_name}`,
            score: districtScores,
            Component: VoterAgreementChart,
            colors: {
                primary: SWAY_COLORS.primary,
                secondary: SWAY_COLORS.primaryLight,
            },
        },
    ].filter((item) => item.score) as IChartChoice[];

    const selectedChart = selected > -1 && components[selected];

    return (
        <div
            ref={ref}
            className={"charts-container legislator-card-charts-container"}
        >
            {components.map((component: IChartChoice, index: number) => {
                if (isLoading) {
                    return (
                        <div
                            key={index}
                            className={"legislator-card-charts-container-div"}
                        >
                            <CircularProgress />
                        </div>
                    );
                }
                return isEmptyObject(component.score) ? null : (
                    <div
                        key={index}
                        onClick={() => handleSetSelected(index)}
                        className={
                            "hover-chart legislator-card-charts-container-div"
                        }
                    >
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

export default LegislatorChartsContainer;
