import { sway } from "sway";

import { isAtLargeLegislator, toFormattedLocaleName } from "app/frontend/sway_utils";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";

import VoterAgreementChart from "app/frontend/components/legislators/charts/VoterAgreementChart";
import VoterDistrictAgreementChart from "app/frontend/components/legislators/charts/VoterDistrictAgreementChart";

// @lat: [[legislators-tab-switching-design#LegislatorChartsPanel's mode prop and chart list]]
interface IProps {
    legislator: sway.ILegislator;
    mode?: "current" | "lifetime";
}

const LegislatorChartsPanel: React.FC<IProps> = ({ legislator, mode = "current" }) => {
    const isLifetime = mode === "lifetime";
    const userScore = isLifetime ? legislator.lifetime_score : legislator.user_legislator_score;
    const [locale] = useSwayLocale();
    if (!userScore) return null;

    const districtScore = userScore.legislator_district_score;
    const localeScore = userScore.legislator_locale_score;
    const isAtLarge = isAtLargeLegislator(legislator.district);

    // @lat: [[scores-and-agreement#Sway is a separate quantity]]
    const formattedLocaleName = toFormattedLocaleName(locale?.name ?? "", false);
    const lifetimeQualifier = isLifetime ? " · lifetime" : "";
    const userTitle = `Your agreement with ${legislator.full_name}${lifetimeQualifier}`;
    const districtTitle = isLifetime
        ? `All districts · lifetime agreement with ${legislator.full_name}`
        : `District ${legislator.district?.number ?? ""} agreement with ${legislator.full_name}`;
    const localeTitle = isLifetime
        ? `${formattedLocaleName} · lifetime agreement with ${legislator.full_name}`
        : `${formattedLocaleName} agreement with ${legislator.full_name}`;

    return (
        <div data-testid="legislator-charts-panel" className="grid gap-5">
            <div
                data-neo-surface="true"
                className="rounded-xl border-neo border-border-strong bg-surface-3 px-4 py-4 shadow-neo"
            >
                <VoterAgreementChart scores={userScore} title={userTitle} />
            </div>
            {!isAtLarge && districtScore && (
                <div
                    data-neo-surface="true"
                    className="rounded-xl border-neo border-border-strong bg-surface-3 px-4 py-4 shadow-neo"
                >
                    <VoterDistrictAgreementChart scores={districtScore} title={districtTitle} />
                </div>
            )}
            {localeScore && (
                <div
                    data-neo-surface="true"
                    className="rounded-xl border-neo border-border-strong bg-surface-3 px-4 py-4 shadow-neo"
                >
                    <VoterDistrictAgreementChart scores={localeScore} title={localeTitle} />
                </div>
            )}
        </div>
    );
};

export default LegislatorChartsPanel;
