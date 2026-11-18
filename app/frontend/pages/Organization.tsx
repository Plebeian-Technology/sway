import { Link, usePage, usePoll } from "@inertiajs/react";
import { ArrowLeft, ArrowRight, Landmark } from "lucide-react";
import { useMemo } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import { useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { localeLabelFor } from "app/frontend/sway_utils";
import { supportTone } from "app/frontend/sway_utils/support";
import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent } from "app/frontend/components/ui/card";
import { cn } from "app/frontend/lib/utils";
import OrganizationTrackControl from "app/frontend/components/organizations/OrganizationTrackControl";
import { sway } from "sway";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import BillRowLink from "app/frontend/components/bill/BillRowLink";

interface IProps {
    organization: sway.IPublicOrganization;
    organization_bill_positions: sway.IPublicOrganizationPosition[];
    current_user_follow_id?: sway.IOrganizationFollowPageProps["current_user_follow_id"];
    user_follow_prefs?: sway.IOrganizationFollowPageProps["user_follow_prefs"];
    current_user_org_defaults?: sway.IOrganizationFollowPageProps["current_user_org_defaults"];
    is_member_of_org_ids?: sway.IOrganizationFollowPageProps["is_member_of_org_ids"];
    org_position_taken?: boolean;
}

// @lat: [[bill-page-polling-props-rationale#BillOfTheMonth.tsx]]
const POLLING_PROPS = [
    "organization",
    "organization_bill_positions",
    "current_user_follow_id",
    "user_follow_prefs",
    "current_user_org_defaults",
    "is_member_of_org_ids",
    "org_position_taken",
];

const Organization: React.FC<IProps> = ({
    organization,
    organization_bill_positions,
    current_user_follow_id,
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

    // @lat: [[locale-name-is-derived#Why localeLabelFor takes a fallback slug]]
    const swayLocaleLabel = useMemo(
        () => localeLabelFor(sway_locales, organization.sway_locale_id, organization.sway_locale_slug),
        [sway_locales, organization.sway_locale_id, organization.sway_locale_slug],
    );

    const isMember = (is_member_of_org_ids ?? []).includes(organization.id);
    const followPrefs = user_follow_prefs?.[organization.id];
    const isMuted = followPrefs?.muted ?? false;

    const positions = organization_bill_positions ?? [];
    const hasIcon = Boolean(organization.icon_url);

    return (
        <div className="space-y-6" data-testid="public-organization-detail">
            <Link
                href={ROUTES.publicOrganizations}
                className="inline-flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground"
            >
                <ArrowLeft className="size-4" aria-hidden="true" />
                All organizations
            </Link>

            <Card className="bg-card/95">
                <CardContent className="flex flex-wrap items-center gap-5 md:flex-nowrap">
                    <div
                        className={cn(
                            "flex size-20 shrink-0 items-center justify-center overflow-hidden rounded-lg border-neo border-border-strong shadow-neo",
                            !hasIcon && "bg-surface-2",
                        )}
                    >
                        {hasIcon ? (
                            <img
                                src={organization.icon_url ?? undefined}
                                alt={`${organization.name} logo`}
                                className="size-full object-cover"
                            />
                        ) : (
                            <Landmark className="size-9 text-muted-foreground" aria-hidden="true" />
                        )}
                    </div>

                    <div className="min-w-0 flex-1">
                        <h1 className="text-2xl font-black text-foreground">{organization.name}</h1>
                        {swayLocaleLabel && <p className="mt-1 text-sm text-muted-foreground">{swayLocaleLabel}</p>}
                    </div>

                    {isSignedIn && (
                        <OrganizationTrackControl
                            organization={organization}
                            followId={current_user_follow_id}
                            isMember={isMember}
                            isMuted={isMuted}
                            isSignedIn={isSignedIn}
                            masterEnabled={org_position_taken}
                            followPrefs={followPrefs}
                            orgDefaults={current_user_org_defaults}
                        />
                    )}
                </CardContent>
            </Card>

            <section className="space-y-4">
                <h2 className="text-lg font-black">Positions</h2>

                {positions.length ? (
                    <div className="space-y-3">
                        {positions.map((position) => (
                            <Card key={position.id} data-testid="public-organization-position">
                                <CardContent className="space-y-3">
                                    <div className="flex flex-wrap items-center justify-between gap-3">
                                        <Badge variant="stamp" tone={supportTone(position.support)}>
                                            {position.support}
                                        </Badge>
                                        <div className="text-xs font-semibold uppercase text-muted-foreground">
                                            {position.origin === "Org-posted" ? (
                                                `Posted by ${organization.name}`
                                            ) : (
                                                "Compiled by Sway"
                                            )}
                                        </div>
                                        <BillRowLink
                                            billId={position.bill_id}
                                            className="inline-flex items-center gap-1 text-sm font-semibold text-primary hover:underline"
                                        >
                                            View bill
                                            <ArrowRight className="size-4" aria-hidden="true" />
                                        </BillRowLink>
                                    </div>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="text-sm leading-6 text-muted-foreground"
                                    />
                                </CardContent>
                            </Card>
                        ))}
                    </div>
                ) : (
                    <p
                        data-testid="public-organization-positions-empty"
                        className="rounded-xl border-neo border-dashed border-border-strong bg-surface-2 px-4 py-8 text-center text-sm text-muted-foreground"
                    >
                        {PARITY_COPY.orgs.noPositions}
                    </p>
                )}
            </section>
        </div>
    );
};

export default Organization;
