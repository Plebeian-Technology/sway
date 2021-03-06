/** @format */

import { Paper, Typography } from "@material-ui/core";
import { toFormattedLocaleName } from "@sway/utils";
import { useEffect } from "react";
import { sway } from "sway";
import {
    useLocaleLegislatorScores,
    useUserLegislatorScore,
} from "../../hooks/scores";
import { IS_MOBILE_PHONE } from "../../utils";
import LegislatorChartsContainer from "./charts/LegislatorChartsContainer";
import LegislatorMobileChartsContainer from "./charts/LegislatorMobileChartsContainer";
import LegislatorCardAvatar from "./LegislatorCardAvatar";
import LegislatorCardSocialRow from "./LegislatorCardSocialRow";

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    legislatorWithScore: sway.ILegislatorWithUserScore;
}

const LegislatorCard: React.FC<IProps> = ({
    user,
    locale,
    legislatorWithScore,
}) => {
    const legislator: sway.ILegislator = legislatorWithScore.legislator;

    const [localeScores, getLocaleScores] = useLocaleLegislatorScores({
        locale,
        legislator,
    });
    const [
        userLegislatorScore,
        getUserLegislatorScore,
    ] = useUserLegislatorScore({ locale, legislator });

    useEffect(() => {
        const load = async () => {
            const awaited = await Promise.all([
                getUserLegislatorScore(),
                getLocaleScores(),
            ])
                .then(() => true)
                .catch(console.error);
            return awaited;
        };
        load().catch(console.error);
    }, [getUserLegislatorScore, getLocaleScores]);

    const isLoading =
        userLegislatorScore === undefined || localeScores === undefined;

    return (
        <div className={"legislator-card"}>
            <Typography
                component={"h4"}
                variant={"h4"}
                color="textPrimary"
                className={"legislator-card-header"}
            >
                {toFormattedLocaleName(legislator.city).toUpperCase()}
            </Typography>
            <Paper className={"legislator-card-container"}>
                <div className={"legislator-card-card-header"}>
                    <LegislatorCardAvatar legislator={legislator} />
                    {user && (
                        <LegislatorCardSocialRow
                            user={user}
                            locale={locale}
                            legislator={legislator}
                        />
                    )}
                </div>
                <div className={"legislator-card-content"}>
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
            </Paper>
        </div>
    );
};

export default LegislatorCard;
