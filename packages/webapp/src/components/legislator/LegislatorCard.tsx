/** @format */

import { toFormattedLocaleName } from "@sway/utils";
import { useEffect } from "react";
import { Animate } from "react-simple-animate";
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
        <Animate play={!isLoading} start={{ opacity: "0%" }} end={{ opacity: "100%" }}>
            <div className="col">
                <div className="row">
                    <div className="col">
                        <h4>{toFormattedLocaleName(legislator.city).toUpperCase()}</h4>
                    </div>
                </div>
                <div className="row">
                    <LegislatorCardAvatar legislator={legislator} />
                    {user && (
                        <LegislatorCardSocialRow
                            user={user}
                            locale={locale}
                            legislator={legislator}
                        />
                    )}
                </div>
                <div className="row my-3">
                    {IS_MOBILE_PHONE ? (
                        <div className="col">
                            <LegislatorMobileChartsContainer
                                user={user}
                                legislator={legislator}
                                userLegislatorScore={userLegislatorScore}
                                localeScores={localeScores}
                                isLoading={isLoading}
                            />
                        </div>
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
        </Animate>
    );
};

export default LegislatorCard;
