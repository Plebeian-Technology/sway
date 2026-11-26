import { Link } from "@inertiajs/react";
import { ArrowRight, Landmark } from "lucide-react";
import { useCallback, useState } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { PREFETCH_CACHE_FOR, ROUTES } from "app/frontend/sway_constants";
import { Card, CardContent } from "app/frontend/components/ui/card";
import OrganizationTrackControl from "app/frontend/components/organizations/OrganizationTrackControl";
import { sway } from "sway";
import { Badge } from "app/frontend/components/ui/badge";
import { cn } from "app/frontend/lib/utils";

interface IProps {
    organization: sway.IPublicOrganization;
    swayLocaleLabel?: string;
    followId?: number | null;
    isMember?: boolean;
    isMuted?: boolean;
    isSignedIn?: boolean;
    masterEnabled?: boolean;
    followPrefs?: sway.IOrgFollowPrefs | null;
    orgDefaults?: sway.IOrgDefaultPrefs | null;
}

const OrganizationCard: React.FC<IProps> = ({
    organization,
    swayLocaleLabel,
    followId,
    isMember = false,
    isMuted = false,
    isSignedIn = false,
    masterEnabled = false,
    followPrefs,
    orgDefaults,
}) => {
    const href = ROUTES.publicOrganization(organization.id);
    const [iconFailed, setIconFailed] = useState(false);
    const handleIconError = useCallback(() => setIconFailed(true), []);
    const showIcon = Boolean(organization.icon_url) && !iconFailed;

    return (
        <Card className="bg-card/95" data-testid="public-organization-card">
            <CardContent className="flex flex-wrap items-center gap-4 md:flex-nowrap">
                <div
                    className={cn(
                        "flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-lg border-neo border-border-strong shadow-neo",
                        !showIcon && "bg-surface-2",
                    )}
                >
                    {showIcon ? (
                        <img
                            src={organization.icon_url ?? undefined}
                            alt={`${organization.name} logo`}
                            className="size-full object-cover"
                            onError={handleIconError}
                        />
                    ) : (
                        <Landmark className="size-7 text-muted-foreground" aria-hidden="true" />
                    )}
                </div>

                <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                        <Link href={href} className="inline-block" prefetch="click" cacheFor={PREFETCH_CACHE_FOR}>
                            <h2 className="text-xl font-black text-foreground hover:underline flex-wrap">
                                {organization.name}
                            </h2>
                        </Link>
                        {followId && (
                            <Badge variant="stamp" tone="success">
                                {PARITY_COPY.orgs.tracking}
                            </Badge>
                        )}
                    </div>
                    {swayLocaleLabel && <p className="mt-1 text-sm text-muted-foreground">{swayLocaleLabel}</p>}
                    {organization.managed_on_sway && (
                        <p className="mt-1 text-sm text-muted-foreground">
                            {PARITY_COPY.orgs.managedOnSway(organization.name)}
                        </p>
                    )}
                </div>

                {isSignedIn && (
                    <OrganizationTrackControl
                        organization={organization}
                        followId={followId}
                        isMember={isMember}
                        isMuted={isMuted}
                        isSignedIn={isSignedIn}
                        masterEnabled={masterEnabled}
                        trackPrefs={followPrefs}
                        orgDefaults={orgDefaults}
                    />
                )}

                <Link
                    href={href}
                    aria-label={`View ${organization.name}`}
                    prefetch="click"
                    cacheFor={PREFETCH_CACHE_FOR}
                    className="inline-flex h-9 shrink-0 cursor-pointer items-center gap-2 rounded-xl border-neo border-border-strong bg-surface-2 px-4 text-sm font-semibold text-foreground shadow-neo transition"
                >
                    View
                    <ArrowRight className="size-4" aria-hidden="true" />
                </Link>
            </CardContent>
        </Card>
    );
};

export default OrganizationCard;
