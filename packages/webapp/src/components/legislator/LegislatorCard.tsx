/** @format */

import { Paper, Typography } from "@mui/material";
import { toFormattedLocaleName } from "@sway/utils";
import { useEffect } from "react";
import { sway } from "sway";
import { useLocaleLegislatorScores, useUserLegislatorScore } from "../../hooks/scores";
import { handleError, IS_MOBILE_PHONE } from "../../utils";
import LegislatorChartsContainer from "./charts/LegislatorChartsContainer";
import LegislatorMobileChartsContainer from "./charts/LegislatorMobileChartsContainer";
import LegislatorCardAvatar from "./LegislatorCardAvatar";
import LegislatorCardSocialRow from "./LegislatorCardSocialRow";

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}

const LegislatorCard: React.FC<IProps> = ({ user, locale, legislator }) => {
    const [localeScores, getLocaleScores] = useLocaleLegislatorScores({
        locale,
        legislator,
    });
    const [userLegislatorScore, getUserLegislatorScore] = useUserLegislatorScore({
        locale,
        legislator,
    });

    useEffect(() => {
        if (userLegislatorScore !== undefined && localeScores !== undefined) return;

        const load = async () => {
            return Promise.all([getUserLegislatorScore(), getLocaleScores()])
                .then(() => true)
                .catch(handleError);
        };
        load().catch(handleError);
    }, [getUserLegislatorScore, getLocaleScores]);

    const isLoading = userLegislatorScore === undefined || localeScores === undefined;

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <Typography component="h4" variant="h4" color="textPrimary">
                        {toFormattedLocaleName(legislator.city).toUpperCase()}
                    </Typography>
                </div>
            </div>
            <Paper className="row">
                <div className="col">
                    <div className="row no-gutter">
                        <LegislatorCardAvatar legislator={legislator} />
                        {user && (
                            <LegislatorCardSocialRow
                                user={user}
                                locale={locale}
                                legislator={legislator}
                            />
                        )}
                    </div>
                    <div className="row">
                        <div className="col">
                            {IS_MOBILE_PHONE ? (
                                <LegislatorMobileChartsContainer
                                    user={user}
                                    legislator={legislator}
                                    userLegislatorScore={userLegislatorScore}
                                    localeScores={localeScores}
                                    isLoading={isLoading}
                                />
                            ) : (
                                <LegislatorChartsContainer
                                    user={user}
                                    legislator={legislator}
                                    userLegislatorScore={userLegislatorScore}
                                    localeScores={localeScores}
                                    isLoading={isLoading}
                                />
                            )}
                        </div>
                    </div>
                </div>
            </Paper>
        </div>
    );
};

export default LegislatorCard;
