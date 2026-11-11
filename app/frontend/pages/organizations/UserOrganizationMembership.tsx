// @lat: [[organizations-memberships-controller-notes#The membership detail page]]

import { router, usePage } from "@inertiajs/react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import MembershipHeader from "app/frontend/components/organizations/MembershipHeader";
import MembersList from "app/frontend/components/organizations/MembersList";
import PendingChangesList from "app/frontend/components/organizations/PendingChangesList";
import PositionsList from "app/frontend/components/organizations/PositionsList";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "app/frontend/components/ui/tabs";
import { useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";
import type { sway } from "sway";

type TabKey = "positions" | "changes" | "members";

const LEGACY_ALIAS: Record<string, TabKey> = {
    positions: "positions",
    changes: "changes",
    approvals: "changes",
    members: "members",
};

interface IPageProps {
    tab?: string;
    [key: string]: unknown;
}

const UserOrganizationMembership: React.FC = () => {
    const membership = useUserOrganizationMembership();
    const tabProp = usePage<IPageProps>().props.tab;

    if (!membership) return null;

    const isAdmin = membership.role === "admin";
    const isSway = membership.organization?.name?.toLowerCase() === "sway";
    const membersOnlyAdminLayout = import.meta.env.PROD && isSway && isAdmin;

    const visibleTabs: TabKey[] = membersOnlyAdminLayout
        ? ["members"]
        : isAdmin
          ? ["positions", "changes", "members"]
          : ["positions", "changes"];

    const defaultTab: TabKey = membersOnlyAdminLayout ? "members" : "positions";
    const fromUrl = tabProp ? LEGACY_ALIAS[tabProp] : undefined;
    const activeTab: TabKey = fromUrl && visibleTabs.includes(fromUrl) ? fromUrl : defaultTab;

    const handleTabChange = (value: string) => {
        const next = value as TabKey;
        router.visit(
            `${ROUTES.organizations.memberships.show(membership.organization.id, membership.id)}?org_tab=${next}`,
            {
                method: "get",
                preserveState: true,
                preserveScroll: true,
                replace: true,
            },
        );
    };

    const positions = membership.positions ?? [];

    if (membersOnlyAdminLayout) {
        return (
            <MembershipHeader membership={membership}>
                <MembersList membership={membership} isAdmin={isAdmin} />
            </MembershipHeader>
        );
    }

    return (
        <MembershipHeader membership={membership}>
            <Tabs value={activeTab} onValueChange={handleTabChange} className="gap-6">
                <TabsList>
                    {visibleTabs.includes("positions") && (
                        <TabsTrigger value="positions">{PARITY_COPY.memberships.tabPositions}</TabsTrigger>
                    )}
                    {visibleTabs.includes("changes") && (
                        <TabsTrigger value="changes">{PARITY_COPY.memberships.tabPendingChanges}</TabsTrigger>
                    )}
                    {visibleTabs.includes("members") && (
                        <TabsTrigger value="members">{PARITY_COPY.memberships.tabMembers}</TabsTrigger>
                    )}
                </TabsList>

                {visibleTabs.includes("positions") && (
                    <TabsContent value="positions">
                        <PositionsList
                            organizationId={(membership.organization as sway.IOrganization).id}
                            positions={positions}
                            isAdmin={isAdmin}
                        />
                    </TabsContent>
                )}
                {visibleTabs.includes("changes") && (
                    <TabsContent value="changes">
                        <PendingChangesList membership={membership} isAdmin={isAdmin} />
                    </TabsContent>
                )}
                {visibleTabs.includes("members") && (
                    <TabsContent value="members">
                        <MembersList membership={membership} isAdmin={isAdmin} />
                    </TabsContent>
                )}
            </Tabs>
        </MembershipHeader>
    );
};

export default UserOrganizationMembership;
