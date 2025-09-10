import { usePage } from "@inertiajs/react";
import UserOrganizationMembership_Position from "app/frontend/pages/organizations/UserOrganizationMembership_Position";
import { sway } from "sway";

interface IPositionWithBill extends sway.IOrganizationPosition {
    bill: sway.IBill;
}

const UserOrganizationMembership_PositionsList = () => {
    const membership = usePage().props.membership as sway.IOrganization &
        sway.IOrganizationMembership & {
            positions: IPositionWithBill[];
            role?: "admin" | "standard";
        };

    return membership.positions.map((position: IPositionWithBill) => (
        <UserOrganizationMembership_Position key={position.id} position={position} />
    ));
};

export default UserOrganizationMembership_PositionsList;
