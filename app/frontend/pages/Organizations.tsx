import { usePage, usePoll } from "@inertiajs/react";

import { useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { localeLabelFor } from "app/frontend/sway_utils";
import OrganizationCard from "app/frontend/components/organizations/OrganizationCard";
import { sway } from "sway";

interface IProps {
    organizations: sway.IPublicOrganization[];
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
    const { sway_locales } = useSwayLocales();
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
                    No organizations yet.
                </p>
            )}
        </div>
    );
};

export default Organizations;
