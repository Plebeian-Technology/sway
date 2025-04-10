/** @format */

import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { Suspense, lazy } from "react";
import { sway } from "sway";
import { useUserLegislatorScore } from "../../hooks/useLegislatorScores";

import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import LegislatorCardSocialRow from "app/frontend/components/legislator/LegislatorCardSocialRow";
import { useLocale } from "app/frontend/hooks/useLocales";
import { IS_MOBILE_PHONE, IS_TABLET } from "app/frontend/sway_constants";
import LegislatorCardAvatar from "./LegislatorCardAvatar";
const LegislatorChartsContainer = lazy(() => import("./charts/LegislatorChartsContainer"));
const LegislatorMobileChartsContainer = lazy(() => import("./charts/LegislatorMobileChartsContainer"));

interface IProps {
    legislator: sway.ILegislator;
    inView: boolean;
}

const LegislatorCard: React.FC<IProps> = ({ legislator, inView }) => {
    const [locale] = useLocale();

    const { items: userLegislatorScore, isLoading } = useUserLegislatorScore(legislator);

    if (!inView) {
        return null;
    }

    return (
        <div className="col border rounded border-primary-subtle p-3">
            <div className="row">
                <div className="col">
                    <h4>{toFormattedLocaleName(locale.city).toUpperCase()}</h4>
                </div>
            </div>
            <div className="row">
                <LegislatorCardAvatar legislator={legislator} />
                <LegislatorCardSocialRow legislator={legislator} />
            </div>
            {userLegislatorScore && (
                <div className="row my-3">
                    {IS_MOBILE_PHONE && !IS_TABLET ? (
                        <Suspense fallback={<CenteredLoading />}>
                            <LegislatorMobileChartsContainer
                                legislator={legislator}
                                userLegislatorScore={userLegislatorScore}
                                isLoading={isLoading}
                            />
                        </Suspense>
                    ) : (
                        <Suspense fallback={<CenteredLoading />}>
                            <LegislatorChartsContainer
                                legislator={legislator}
                                userLegislatorScore={userLegislatorScore}
                                isLoading={isLoading}
                            />
                        </Suspense>
                    )}
                </div>
            )}
        </div>
    );
};

export default LegislatorCard;
