// @lat: [[organizations-memberships-controller-notes#NewUserOrganizationPosition.tsx, the New Position page]]

import { usePage } from "@inertiajs/react";
import type { sway } from "sway";

import NewPositionDialog from "app/frontend/components/organizations/NewPositionDialog";
import UserOrganizationMembership from "app/frontend/pages/organizations/UserOrganizationMembership";
import { useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";

interface IPageProps {
    bills?: sway.IBill[];
    [key: string]: unknown;
}

const NewUserOrganizationPosition: React.FC = () => {
    const membership = useUserOrganizationMembership();
    const bills = usePage<IPageProps>().props.bills ?? [];

    if (!membership?.organization?.id) {
        return <UserOrganizationMembership />;
    }

    const membershipHref = ROUTES.organizations.memberships.show(membership.organization.id, membership.id);

    return (
        <>
            <UserOrganizationMembership />
            <NewPositionDialog
                open
                organizationId={membership.organization.id}
                bills={bills}
                membershipHref={membershipHref}
            />
        </>
    );
};

export default NewUserOrganizationPosition;
