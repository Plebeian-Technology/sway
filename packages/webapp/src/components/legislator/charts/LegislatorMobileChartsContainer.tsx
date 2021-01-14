/** @format */

import { CircularProgress, IconButton, SvgIconTypeMap, Typography } from "@material-ui/core";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { Grade, MapOutlined } from "@material-ui/icons";
import React from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { swayBlue } from "../../../utils";
import DialogWrapper from "../../dialogs/DialogWrapper";
import VoterAgreementChart from "./VoterAgreementChart";

interface IProps {
    user: sway.IUser | undefined;
    legislator: sway.ILegislator;
    userLegislatorScore: sway.IUserLegislatorScore | undefined;
    districtScores: sway.IUserLegislatorScore | undefined;
    isLoading: boolean;
}

interface IChartChoice {
    title: string;
    label: string;
    score: sway.IUserLegislatorScore;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
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
    }
}

const LegislatorMobileChartsContainer: React.FC<IProps> = ({
    legislator,
    userLegislatorScore,
    districtScores,
    isLoading,
}) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = React.useRef(
        null,
    );
    const [open, setOpen] = useOpenCloseElement(ref);

    const [selected, setSelected] = React.useState<number>(0);
    const [expanded, setExpanded] = React.useState<number | null>(null);

    const handleSetExpanded = (index: number) => {
        setOpen(true);
        setExpanded(index);
    };
    const handleClose = () => {
        setOpen(false);
        setExpanded(null);
    };

    const components = [
        {
            Icon: Grade,
            label: "You",
            title: `Your Sway Score with ${legislator.full_name}`,
            score: userLegislatorScore,
            Component: VoterAgreementChart,
            colors: {
                primary: "rgba(255,99,132,0.2)",
                secondary: "rgba(255,99,132,1)",
            },
        },
        {
            Icon: MapOutlined,
            label: "District",
            title: `District ${legislator.district} Sway Scores for ${legislator.full_name}`,
            score: districtScores,
            Component: VoterAgreementChart,
            colors: {
                primary: "rgba(102,51,153,0.2)",
                secondary: "rgba(102,51,153,1)",
            },
        },
    ].filter(item => item.score) as IChartChoice[];

    const selectedChart = expanded && components[expanded];

    return (
        <div
            ref={ref}
            className={"charts-container legislator-card-charts-container"}
        >
            <div className={"legislator-card-charts-selector"}>
                {components.map((component: IChartChoice, index: number) => {
                    return (
                        <div
                            key={index}
                            onClick={() => setSelected(index)}
                            style={{
                                textAlign: "center",
                                border: `2px solid ${
                                    index === selected
                                        ? swayBlue
                                        : "transparent"
                                }`,
                                borderRadius: "5px",
                                padding: 10,
                                paddingLeft: index === 0 ? 20 : 10,
                                paddingRight: index === 0 ? 20 : 10,
                            }}
                        >
                            <Typography component={"p"} variant={"body2"}>
                                {component.label}
                            </Typography>
                            <IconButton
                                onClick={() => setSelected(index)}
                                aria-label={component.title}
                                style={{ padding: 0 }}
                            >
                                {
                                    <component.Icon
                                        style={{
                                            color:
                                                index === selected
                                                    ? swayBlue
                                                    : "initial",
                                        }}
                                    />
                                }
                            </IconButton>
                        </div>
                    );
                })}
            </div>
            {components.map((component: IChartChoice, index: number) => {
                if (index !== selected) return null;
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

                return !component.score ? null : (
                    <div
                        key={index}
                        className={"legislator-card-charts-container-div"}
                        onClick={() => handleSetExpanded(index)}
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

export default LegislatorMobileChartsContainer;
