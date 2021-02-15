/** @format */

import { Avatar, Paper, Typography } from "@material-ui/core";
import copy from "copy-to-clipboard";
import React, { useEffect, useState } from "react";
import { fire, sway } from "sway";
import {
    handleError,
    IS_COMPUTER_WIDTH,
    IS_MOBILE_PHONE,
    swayFireClient,
    notify,
} from "../../utils";
import { IS_DEVELOPMENT } from "@sway/utils";
import LegislatorChartsContainer from "./charts/LegislatorChartsContainer";
import LegislatorMobileChartsContainer from "./charts/LegislatorMobileChartsContainer";
import LegislatorEmail from "./LegislatorEmail";
import LegislatorPhone from "./LegislatorPhone";
interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    legislatorWithScore: sway.ILegislatorWithUserScore;
}

export interface IAggregateResponseData {
    userAgreedPercentile: number;
    userDisagreedPercentile: number;
    userAbstainedPercentile: number;
    userUnmatchedPercentile: number;
    userAgreedPercent: number;
    userDisagreedPercent: number;
    userAbstainedPercent: number;
    userUnmatchedPercent: number;
    sortedAgreedPercents: number[];
    sortedDisagreedPercents: number[];
    sortedAbstainedPercents: number[];
    sortedUnmatchedPercents: number[];
}

const initialDistrictScores = {
    externalLegislatorId: "",
    totalUserVotes: 0,
    totalUnmatchedLegislatorVote: 0,
    totalUserLegislatorAbstained: 0,
    totalUserLegislatorAgreed: 0,
    totalUserLegislatorDisagreed: 0,
    userLegislatorVotes: [],
};
const initialState = {
    score: undefined,
    districtScores: initialDistrictScores,
    aggregated: undefined,
    isLoading: true,
};

interface IState {
    score: sway.IUserLegislatorScore | undefined;
    districtScores: sway.IUserLegislatorScore;
    aggregated: IAggregateResponseData | undefined;
    isLoading: boolean;
}

const LegislatorCard: React.FC<IProps> = ({
    user,
    locale,
    legislatorWithScore,
}) => {
    const [state, setState] = useState<IState>(initialState);

    const legislator: sway.ILegislator = legislatorWithScore.legislator;
    const uid: string | undefined = user?.uid;

    const { aggregated, districtScores } = state;
    const { externalId, district } = legislator;
    const hasAggregated = Boolean(aggregated);

    useEffect(() => {
        const getDistrictScores = (): Promise<sway.IUserLegislatorScore | void> => {
            return swayFireClient(locale)
                .userDistrictScores()
                .get(externalId, district)
                .catch((error: Error) => {
                    if (IS_DEVELOPMENT) {
                        console.log("error getting district scores");
                        console.error(error);
                    }
                });
        };

        if (
            uid &&
            locale &&
            externalId &&
            typeof district === "number" &&
            !hasAggregated
        ) {
            getDistrictScores()
                .then((districtScoreData) => {
                    setState((prevState: IState) => ({
                        ...prevState,
                        districtScores:
                            districtScoreData || initialDistrictScores,
                        isLoading: false,
                    }));
                })
                .catch(handleError);
        } else {
            setState((prevState: IState) => ({
                ...prevState,
                isLoading: false,
            }));
        }

        if (uid && externalId) {
            return swayFireClient(locale)
                .userLegislatorScores()
                .listen(
                    externalId,
                    uid,
                    async (
                        snapshot: fire.TypedDocumentSnapshot<sway.IUserLegislatorScore>,
                    ) => {
                        const data =
                            snapshot.data() ||
                            ({} as sway.IUserLegislatorScore);
                        setState((prevState: IState) => ({
                            ...prevState,
                            score: data,
                        }));
                    },
                );
        }
    }, [uid, locale, externalId, district, hasAggregated]);

    const isActive = legislator.active ? "Active" : "Inactive";
    const subheader = () =>
        legislator.district === 0
            ? `At-Large - ${isActive}`
            : `District - ${legislator.district} - ${isActive}`;

    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied!",
                    message: `Copied ${value} to clipboard`,
                }),
        });
    };

    return (
        <div className={"legislator-card"}>
            <Typography
                component={"h4"}
                variant={"h4"}
                color="textPrimary"
                className={"legislator-card-header"}
            >
                {legislator.city.toUpperCase()}
            </Typography>
            <Paper className={"legislator-card-container"}>
                <div className={"legislator-card-card-header"}>
                    <div
                        className={"legislator-card-sub-card-header"}
                        style={{
                            justifyContent: IS_MOBILE_PHONE
                                ? "flex-start"
                                : "flex-start",
                        }}
                    >
                        <div className={"legislator-card-sub-card-header-item"}>
                            <Avatar
                                aria-label={legislator.full_name + " avatar"}
                                className={"legislator-card-avatar"}
                                src={
                                    legislator.photoURL &&
                                    legislator.photoURL?.startsWith("https")
                                        ? legislator.photoURL
                                        : ""
                                }
                                alt={legislator.full_name + " avatar"}
                            />
                        </div>
                        <div className={"legislator-card-sub-card-header-item"}>
                            <Typography variant={"body1"}>
                                {`${legislator.title} ${legislator.full_name}`}
                            </Typography>
                            <Typography variant={"body2"}>
                                {subheader()}
                            </Typography>
                        </div>
                    </div>
                    {legislator.phone && (
                        <LegislatorPhone
                            phone={legislator.phone}
                            handleCopy={handleCopy}
                        />
                    )}
                    {legislator.email && (
                        <LegislatorEmail
                            email={legislator.email}
                            handleCopy={handleCopy}
                        />
                    )}
                </div>
                <div className={"legislator-card-content"}>
                    {IS_COMPUTER_WIDTH ? (
                        <LegislatorChartsContainer
                            user={user}
                            legislator={legislator}
                            userLegislatorScore={state.score}
                            districtScores={districtScores}
                            isLoading={state.isLoading}
                        />
                    ) : (
                        <LegislatorMobileChartsContainer
                            user={user}
                            legislator={legislator}
                            userLegislatorScore={state.score}
                            districtScores={districtScores}
                            isLoading={state.isLoading}
                        />
                    )}
                </div>
            </Paper>
        </div>
    );
};

export default LegislatorCard;
