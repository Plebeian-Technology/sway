// @lat: [[organizations-memberships-controller-notes#MembershipHeader.tsx, the membership detail header]]

import { router } from "@inertiajs/react";
import { capitalize } from "lodash";
import { LogOut } from "lucide-react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import type { IMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";

interface IProps extends React.PropsWithChildren {
    membership: IMembership;
}

const MembershipHeader: React.FC<IProps> = ({ membership, children }) => {
    const role = membership.role ?? "standard";
    const tone = role === "admin" ? "primary" : "neutral";
    const orgName = membership.organization.name;
    const confirm = useConfirm();

    const handleLeave = async () => {
        const confirmed = await confirm({
            title: `Leave ${orgName}?`,
            description:
                role === "admin"
                    ? "If you are the only admin, you must promote another admin first."
                    : "You will lose access to positions and pending changes for this organization.",
            confirmLabel: "Leave",
            tone: "destructive",
        });
        if (!confirmed) return;

        router.delete(ROUTES.organizations.memberships.leave(membership.organization.id), {
            preserveScroll: true,
        });
    };

    return (
        <div className="mx-auto w-full max-w-6xl space-y-6 px-4 py-8">
            <div className="flex items-start gap-4">
                <img
                    src={membership.organization.icon_url || "/images/organization-placeholder.png"}
                    alt=""
                    className="h-16 w-16 rounded-lg border-neo border-border-strong object-cover"
                />
                <div className="min-w-0 flex-1 space-y-1">
                    <h1 className="truncate text-2xl font-semibold tracking-tight">{orgName}</h1>
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <span>Your role:</span>
                        <Badge variant="stamp" tone={tone}>
                            {capitalize(role)}
                        </Badge>
                    </div>
                </div>
                <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={handleLeave}
                    data-testid="org-leave-button"
                    className="text-destructive hover:bg-destructive hover:text-destructive-foreground"
                >
                    <LogOut className="mr-1 size-3.5" aria-hidden />
                    Leave
                </Button>
            </div>
            {children}
        </div>
    );
};

export default MembershipHeader;
