/** @format */

import { logDev, toFormattedLocaleName } from "@sway/utils";
import React, { useCallback, useEffect, useMemo } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import { useLocaleLegislatorScores, useUserLegislatorScore } from "../../hooks/useLegislatorScores";
import { handleError, IS_MOBILE_PHONE, IS_TABLET } from "../../utils";
import SwaySpinner from "../SwaySpinner";
import LegislatorChartsContainer from "./charts/LegislatorChartsContainer";
import LegislatorMobileChartsContainer from "./charts/LegislatorMobileChartsContainer";
import LegislatorCardAvatar from "./LegislatorCardAvatar";
import LegislatorCardSocialRow from "./LegislatorCardSocialRow";

interface IProps {
    legislator: sway.ILegislator;
}

const LegislatorCard: React.FC<IProps> = ({ legislator }) => {
    const [localeScores, getLocaleScores, setLocaleScores] = useLocaleLegislatorScores({
        externalId: legislator.externalId,
        district: legislator.district,
        regionCode: legislator.regionCode,
    });
    const [userLegislatorScore, getUserLegislatorScore, setUserLegislatorScores] =
        useUserLegislatorScore({
            externalId: legislator.externalId,
            district: legislator.district,
            regionCode: legislator.regionCode,
        });

    const isLoading = useMemo(
        () => !userLegislatorScore || !localeScores,
        [userLegislatorScore, localeScores],
    );

    useEffect(() => {
        Promise.all([getUserLegislatorScore(), getLocaleScores()])
            .then(([newUserLegislatorScores, newLocaleScores]) => {
                if (newLocaleScores) {
                    setLocaleScores(newLocaleScores);
                }
                if (newUserLegislatorScores) {
                    setUserLegislatorScores(newUserLegislatorScores);
                }
            })
            .catch(handleError);
    }, [getUserLegislatorScore, getLocaleScores, setLocaleScores, setUserLegislatorScores]);

    if (legislator.externalId.includes("M000687")) {
        logDev("LegislatorCard.scores", {
            legislator: legislator.externalId,
            localeScores,
            userLegislatorScore,
        });
    }

    const render = useCallback(
        ({ style }: { style: React.CSSProperties | undefined }) => (
            <div className="col" style={style}>
                <div className="row">
                    <div className="col">
                        <h4>{toFormattedLocaleName(legislator.city).toUpperCase()}</h4>
                    </div>
                </div>
                <div className="row">
                    <LegislatorCardAvatar legislator={legislator} />
                    <LegislatorCardSocialRow legislator={legislator} />
                </div>
                <div className="row my-3">
                    {IS_MOBILE_PHONE && !IS_TABLET ? (
                        <div className="col">
                            <LegislatorMobileChartsContainer
                                legislator={legislator}
                                userLegislatorScore={userLegislatorScore}
                                localeScores={localeScores}
                                isLoading={isLoading}
                            />
                        </div>
                    ) : (
                        <LegislatorChartsContainer
                            legislator={legislator}
                            userLegislatorScore={userLegislatorScore}
                            localeScores={localeScores}
                            isLoading={isLoading}
                        />
                    )}
                </div>
            </div>
        ),
        [isLoading, legislator, localeScores, userLegislatorScore],
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
