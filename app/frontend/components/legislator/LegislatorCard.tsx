/** @format */

import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { useCallback } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import { useUserLegislatorScore } from "../../hooks/useLegislatorScores";

import { useLocale } from "app/frontend/hooks/useLocales";
import { IS_MOBILE_PHONE, IS_TABLET } from "app/frontend/sway_constants";
import SwaySpinner from "../SwaySpinner";
import LegislatorCardAvatar from "./LegislatorCardAvatar";
import LegislatorChartsContainer from "./charts/LegislatorChartsContainer";
import LegislatorMobileChartsContainer from "./charts/LegislatorMobileChartsContainer";

interface IProps {
    legislator: sway.ILegislator;
}

const LegislatorCard: React.FC<IProps> = ({ legislator }) => {
    const [locale] = useLocale();

    const { items: userLegislatorScore, isLoading } = useUserLegislatorScore(legislator);

    const render = useCallback(
        ({ style }: { style: React.CSSProperties | undefined }) => (
            <div className="col border rounded border-primary-subtle p-3" style={style}>
                <div className="row">
                    <div className="col">
                        <h4>{toFormattedLocaleName(locale.city).toUpperCase()}</h4>
                    </div>
                </div>
                <div className="row">
                    <LegislatorCardAvatar legislator={legislator} />
                    {/* <LegislatorCardSocialRow legislator={legislator} /> */}
                </div>
                {userLegislatorScore && <div className="row my-3">
                    {IS_MOBILE_PHONE && !IS_TABLET ? (
                        <div className="col">
                            <LegislatorMobileChartsContainer
                                legislator={legislator}
                                userLegislatorScore={userLegislatorScore}
                                isLoading={isLoading}
                            />
                        </div>
                    ) : (
                        <LegislatorChartsContainer
                            legislator={legislator}
                            userLegislatorScore={userLegislatorScore}
                            isLoading={isLoading}
                        />
                    )}
                </div>}
            </div>
        ),
        [isLoading, legislator, locale.city, userLegislatorScore],
    );

    return (
        <>
            {isLoading && <SwaySpinner message={"Loading Legislator..."} />}
            <Animate
                play={!isLoading}
                start={{ opacity: 0 }}
                end={{ opacity: 1 }}
                render={render}
            ></Animate>
        </>
    );
};

export default LegislatorCard;
