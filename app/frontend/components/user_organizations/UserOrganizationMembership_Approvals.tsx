import UserOrganizationMembership_Approval from "app/frontend/components/user_organizations/UserOrganizationMembership_Approval";
import { IMembership, useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";

const UserOrganizationMembership_Approvals = () => {
    const membership = useUserOrganizationMembership() as IMembership;

    return membership.pending_changes.map((change) => (
        <UserOrganizationMembership_Approval change={change} key={change.id} />
    ));
};

export default UserOrganizationMembership_Approvals;
