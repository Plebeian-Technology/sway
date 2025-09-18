import { router, usePage } from "@inertiajs/react";
import LayoutWithPage from "app/frontend/components/layouts/Layout";
import { IMembership, useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import UserOrganizationMembership_Approvals from "app/frontend/components/user_organizations/UserOrganizationMembership_Approvals";
import UserOrganizationMembership_Members from "app/frontend/components/user_organizations/UserOrganizationMembership_Members";
import UserOrganizationMembership_Positions from "app/frontend/components/user_organizations/UserOrganizationMembership_PositionsList";
import { capitalize } from "lodash";
import { PropsWithChildren } from "react";
import { Tab, Tabs } from "react-bootstrap";
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";

const Header = ({ membership, children }: PropsWithChildren & { membership: IMembership }) => {
    return (
        <div className="container d-grid gap-4">
            <div className="row align-items-center">
                <div className="col">
                    <h1>
                        {membership.organization.name}: Role - {capitalize(membership.role)}
                    </h1>
                </div>
                <div className="col text-end">
                    <img
                        src={membership.organization.icon_path || "/images/organization-placeholder.png"}
                        alt="Organization Icon"
                        style={{ maxHeight: "100px", maxWidth: "100px" }}
                        className="me-2"
                    />
                </div>
            </div>
            {children}
        </div>
    );
};

const UserOrganizationMembership = () => {
    const membership = useUserOrganizationMembership();
    const isSway = membership?.organization?.name?.toLowerCase() === "sway";

    const key = (usePage().props.tab as string) || (isSway ? "members" : "positions");

    const onSelectTab = (k: string | null) => {
        if (k && membership) {
            // router.visit(`/user_organization_memberships/${membership.id}?tab=${k}`, {
            router.visit(
                `${ROUTES.organizations.memberships.show(membership.organization.id, membership.id)}?tab=${k}`,
                {
                    method: "get",
                    preserveScroll: true,
                },
            );
        }
    };

    if (!membership) {
        return null;
    }

    // If not admin, show only positions list (no tabs)
    if (membership.role !== "admin") {
        return (
            <Header membership={membership}>
                <Tabs activeKey={key} onSelect={onSelectTab} variant={IS_MOBILE_PHONE ? "pills" : "tabs"} fill>
                    <Tab eventKey="positions" title={<b>Positions</b>}>
                        <div className="d-grid gap-4">
                            <UserOrganizationMembership_Positions />
                        </div>
                    </Tab>
                    <Tab eventKey="approvals" title={<b>Pending Position Changes</b>}>
                        <div className="d-grid gap-4">
                            <UserOrganizationMembership_Approvals />
                        </div>
                    </Tab>
                </Tabs>
            </Header>
        );
    }

    // In production, Sway is not used for creating positions on bills.
    // In developemnt, it's the organization we have.
    if (import.meta.env.PROD && isSway) {
        return (
            <Header membership={membership}>
                <UserOrganizationMembership_Members />
            </Header>
        );
    }

    return (
        <Header membership={membership}>
            <Tabs activeKey={key} onSelect={onSelectTab} variant={IS_MOBILE_PHONE ? "pills" : "tabs"} fill>
                <Tab eventKey="positions" title={<b>Positions</b>}>
                    <div className="d-grid gap-4">
                        <UserOrganizationMembership_Positions />
                    </div>
                </Tab>
                <Tab eventKey="approvals" title={<b>Pending Position Changes</b>}>
                    <div className="d-grid gap-4">
                        <UserOrganizationMembership_Approvals />
                    </div>
                </Tab>
                <Tab eventKey="members" title={<b>Members</b>}>
                    <div className="d-grid gap-4">
                        <UserOrganizationMembership_Members />
                    </div>
                </Tab>
            </Tabs>
        </Header>
    );
};

const PageLayout = (page: React.JSX.Element) => LayoutWithPage({ ...page, props: { ...page.props, withFade: false } });
UserOrganizationMembership.layout = PageLayout;
export default UserOrganizationMembership;
