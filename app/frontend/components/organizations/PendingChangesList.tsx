// @lat: [[organizations-v2-list-cards#PendingChangesList.tsx, the current (V2) pending-changes list]]

import { usePage } from "@inertiajs/react";

import PendingChangeCard from "app/frontend/components/organizations/PendingChangeCard";
import type { IMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";

interface IProps {
    membership: IMembership;
    isAdmin: boolean;
}

interface IPageProps {
    new_position_id?: number | null;
    [key: string]: unknown;
}

const PendingChangesList: React.FC<IProps> = ({ membership, isAdmin }) => {
    const newPositionId = usePage<IPageProps>().props.new_position_id;
    const changes = membership.pending_changes ?? [];

    if (!changes.length) {
        return (
            <div data-testid="org-membership-accepted" aria-live="polite">
                <p className="text-sm text-muted-foreground">No pending changes.</p>
            </div>
        );
    }

    return (
        <div className="space-y-4" data-testid="org-membership-accepted" aria-live="polite">
            {changes.map((change) => (
                <PendingChangeCard
                    key={change.id}
                    change={change}
                    membership={membership}
                    isAdmin={isAdmin}
                    isFocused={change.id === newPositionId}
                />
            ))}
        </div>
    );
};

export default PendingChangesList;
