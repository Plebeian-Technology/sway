// @lat: [[organizations-memberships-controller-notes#UserOrganizationMembershipsList.tsx, the memberships dashboard]]

import { useUser } from "app/frontend/hooks/users/useUser";

import MembershipCard from "app/frontend/components/organizations/MembershipCard";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const UserOrganizationMembershipsList: React.FC = () => {
    const user = useUser();
    const memberships = user?.memberships ?? [];
    const hasMemberships = memberships.length > 0;

    return (
        <div
            className={hasMemberships ? "mx-auto w-full max-w-6xl space-y-6 px-4 py-8" : "mx-auto max-w-3xl px-4 py-8"}
        >
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight" data-testid="my-organizations-heading">
                    {PARITY_COPY.memberships.title}
                </h1>
                {hasMemberships ? (
                    <p className="text-sm text-muted-foreground">
                        Organizations where you can review positions and manage members.
                    </p>
                ) : (
                    <p className="text-sm text-muted-foreground" data-testid="my-organizations-empty">
                        {PARITY_COPY.memberships.activeEmpty}
                    </p>
                )}
            </div>
            {hasMemberships && (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    {memberships.map((membership) => (
                        <MembershipCard key={membership.id} membership={membership} />
                    ))}
                </div>
            )}
        </div>
    );
};

export default UserOrganizationMembershipsList;
