import { router, usePage } from "@inertiajs/react";
import UserOrganizationMembership_Position from "app/frontend/components/user_organizations/UserOrganizationMembership_Position";
import { ROUTES } from "app/frontend/sway_constants";
import { Button } from "react-bootstrap";
import { FiPlus } from "react-icons/fi";
import { sway } from "sway";

interface IPositionWithBill extends sway.IOrganizationPosition {
    bill: sway.IBill;
}

const UserOrganizationMembership_PositionsList = ({
    showAddNewPositionButton = true,
}: {
    showAddNewPositionButton?: boolean;
}) => {
    const membership = usePage().props.membership as sway.IOrganization &
        sway.IOrganizationMembership & {
            positions: IPositionWithBill[];
            role?: "admin" | "standard";
        };

    const handleAddNewPosition = () => {
        if (membership.organization.id) {
            router.visit(ROUTES.organizations.positions.new(membership.organization.id));
        }
    };

    return (
        <div className="d-grid gap-4">
            {showAddNewPositionButton && (
                <div className="row">
                    <div className="col">
                        <Button onClick={handleAddNewPosition}>
                            <FiPlus />
                            &nbsp;Add New Position
                        </Button>
                    </div>
                </div>
            )}
            {membership.positions.map((position: IPositionWithBill) => (
                <UserOrganizationMembership_Position key={position.id} position={position} />
            ))}
        </div>
    );
};

export default UserOrganizationMembership_PositionsList;
