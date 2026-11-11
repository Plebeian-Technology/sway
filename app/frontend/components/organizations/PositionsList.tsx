import { Link } from "@inertiajs/react";
import { Plus } from "lucide-react";

import { Button } from "app/frontend/components/ui/button";
import PositionCard from "app/frontend/components/organizations/PositionCard";
import { ROUTES } from "app/frontend/sway_constants";
import type { IPositionWithBill } from "app/frontend/hooks/users/useUserOrganizationMembership";

interface IProps {
    organizationId: number;
    positions: IPositionWithBill[];
    isAdmin: boolean;
    showAddButton?: boolean;
}

const PositionsList: React.FC<IProps> = ({ organizationId, positions, isAdmin, showAddButton = true }) => {
    return (
        <div className="space-y-4">
            {showAddButton && isAdmin && (
                <div className="flex justify-end">
                    <Link href={ROUTES.organizations.positions.new(organizationId)}>
                        <Button type="button">
                            <Plus className="mr-1 size-4" aria-hidden />
                            Add New Position
                        </Button>
                    </Link>
                </div>
            )}
            {positions.length === 0 ? (
                <p className="text-sm text-muted-foreground">No positions yet.</p>
            ) : (
                positions.map((position) => (
                    <PositionCard
                        key={position.id}
                        position={position}
                        organizationId={organizationId}
                        isAdmin={isAdmin}
                    />
                ))
            )}
        </div>
    );
};

export default PositionsList;
