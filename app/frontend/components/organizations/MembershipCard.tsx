// @lat: [[organizations-v2-list-cards#MembershipCard.tsx, the current (V2) membership summary card]]

import { Link } from "@inertiajs/react";
import { ArrowRight } from "lucide-react";
import { capitalize } from "lodash";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { PREFETCH_CACHE_FOR, ROUTES } from "app/frontend/sway_constants";
import { sway } from "sway";

const initialsOf = (name: string): string =>
    name
        .split(/\s+/)
        .slice(0, 2)
        .map((w) => w[0]?.toUpperCase() ?? "")
        .join("") || "?";

interface IProps {
    membership: sway.IOrganizationMembership;
}

const MembershipCard: React.FC<IProps> = ({ membership }) => {
    const { organization, role } = membership;
    const roleTone = role === "admin" ? "primary" : "neutral";
    const href = ROUTES.organizations.memberships.show(organization.id, membership.id);
    const positionsCount = membership.positions_count ?? 0;
    const pendingCount = membership.pending_changes_count ?? 0;

    return (
        <Card className="flex h-full flex-col" data-testid="membership-card">
            <CardHeader className="flex items-center gap-3">
                {organization.icon_url ? (
                    <img
                        src={organization.icon_url}
                        alt=""
                        className="h-12 w-12 rounded-lg border-neo border-border-strong object-cover"
                    />
                ) : (
                    <div
                        aria-hidden
                        className="flex h-12 w-12 items-center justify-center rounded-lg border-neo border-border-strong bg-muted text-sm font-semibold"
                    >
                        <span className="tabular-nums lining-nums">{initialsOf(organization.name)}</span>
                    </div>
                )}
                <CardTitle className="flex-1 text-lg leading-tight">{organization.name}</CardTitle>
                <Badge variant="stamp" tone={roleTone}>
                    {capitalize(role)}
                </Badge>
            </CardHeader>
            <CardContent className="flex flex-1 flex-col justify-between gap-4">
                <dl className="grid grid-cols-2 gap-3 text-sm">
                    <div>
                        <dt className="text-muted-foreground uppercase tracking-wide text-xs">Positions</dt>
                        <dd className="text-xl font-semibold tabular-nums lining-nums">{positionsCount}</dd>
                    </div>
                    <div>
                        <dt className="text-muted-foreground uppercase tracking-wide text-xs">Pending</dt>
                        <dd className="text-xl font-semibold tabular-nums lining-nums">{pendingCount}</dd>
                    </div>
                </dl>
                <Link href={href} className="block" prefetch="click" cacheFor={PREFETCH_CACHE_FOR}>
                    <Button className="w-full" type="button">
                        View Organization
                        <ArrowRight className="ml-1 size-4" aria-hidden />
                    </Button>
                </Link>
            </CardContent>
        </Card>
    );
};

export default MembershipCard;
