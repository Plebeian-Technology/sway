import { usePage, usePoll } from "@inertiajs/react";

import { useSwayLocale, useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { localeLabelFor, toFormattedLocaleName } from "app/frontend/sway_utils";
import OrganizationCard from "app/frontend/components/organizations/OrganizationCard";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { Label } from "app/frontend/components/ui/label";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { sway } from "sway";

interface IAppliedFilters {
    locale_id?: string | null;
    sway_locale_id?: string | null;
    org_search?: string | null;
}

interface IProps {
    organizations: sway.IPublicOrganization[];
    applied_filters?: IAppliedFilters;
    user_follows?: sway.IOrganizationFollowPageProps["user_follows"];
    user_follow_prefs?: sway.IOrganizationFollowPageProps["user_follow_prefs"];
    current_user_org_defaults?: sway.IOrganizationFollowPageProps["current_user_org_defaults"];
    is_member_of_org_ids?: sway.IOrganizationFollowPageProps["is_member_of_org_ids"];
    org_position_taken?: boolean;
}

// @lat: [[bill-page-polling-props-rationale#BillOfTheMonth.tsx]]
const POLLING_PROPS = [
    "organizations",
    "user_follows",
    "user_follow_prefs",
    "current_user_org_defaults",
    "is_member_of_org_ids",
    "org_position_taken",
];

const Organizations: React.FC<IProps> = ({
    organizations,
    user_follows,
    user_follow_prefs,
    current_user_org_defaults,
    is_member_of_org_ids,
    org_position_taken = false,
}) => {
    usePoll(15000, { only: POLLING_PROPS }, { background: "pause" });
    const { sway_locales, options } = useSwayLocales();
    const [swayLocale, getSwayLocale, pendingSwayLocaleId] = useSwayLocale();
    // @lat: [[public-organizations-endpoint#What a signed-out reader is never sent]]
    const { props } = usePage<sway.IPageProps>();
    const isSignedIn = Boolean(props.user?.id);

    const orgs = organizations ?? [];

    return (
        <div className="space-y-6">
            <div className="space-y-2">
                <h1 className="text-2xl font-black">Organizations</h1>
                <p className="text-sm text-muted-foreground">
                    Browse civic organizations and the positions they've taken on legislation.
                </p>
            </div>

            <div className="flex items-center gap-3 rounded-xl border border-border bg-surface-2 px-4 py-3">
                <Label htmlFor="organizations-locale" className="shrink-0">
                    Locale
                </Label>
                <SwayLocalePicker
                    id="organizations-locale"
                    options={options}
                    value={pendingSwayLocaleId ?? swayLocale?.id}
                    onChange={getSwayLocale}
                    className="min-w-0 flex-1"
                />
            </div>

            {orgs.length ? (
                <div className="space-y-4">
                    {orgs.map((organization) => {
                        const followId = user_follows?.[organization.id] ?? null;
                        const isMember = (is_member_of_org_ids ?? []).includes(organization.id);
                        const followPrefs = user_follow_prefs?.[organization.id];
                        const isMuted = followPrefs?.muted ?? false;

                        // @lat: [[locale-name-is-derived#Why localeLabelFor takes a fallback slug]]
                        return (
                            <OrganizationCard
                                key={organization.id}
                                organization={organization}
                                swayLocaleLabel={localeLabelFor(
                                    sway_locales,
                                    organization.sway_locale_id,
                                    organization.sway_locale_slug,
                                )}
                                followId={isSignedIn ? followId : undefined}
                                isMember={isMember}
                                isMuted={isMuted}
                                isSignedIn={isSignedIn}
                                masterEnabled={org_position_taken}
                                followPrefs={isSignedIn ? followPrefs : undefined}
                                orgDefaults={isSignedIn ? current_user_org_defaults : undefined}
                            />
                        );
                    })}
                </div>
            ) : (
                <p
                    data-testid="public-organizations-empty"
                    className="rounded-xl border-neo border-dashed border-border-strong bg-surface-2 px-4 py-8 text-center text-sm text-muted-foreground"
                >
                    {PARITY_COPY.orgs.noneFound(toFormattedLocaleName(swayLocale?.name ?? ""))}
                </p>
            )}
        </div>
    );
};

export default Organizations;
