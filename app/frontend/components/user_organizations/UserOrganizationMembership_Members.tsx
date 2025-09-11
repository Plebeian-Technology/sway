import { router, usePage } from "@inertiajs/react";
import { IMembership, useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";
import { Button, Form, Table } from "react-bootstrap";

interface IOrganizationMember {
    id: number;
    full_name: string;
    email: string;
    role: "admin" | "standard";
}

const UserOrganizationMembership_Members = () => {
    const key = (usePage().props.tab as string) || "positions";
    const membership = useUserOrganizationMembership() as IMembership;

    // Handler for deleting a member (replace with API call as needed)
    const handleDeleteMember = (memberId: number) => {
        if (!confirm("Are you sure you want to remove this member?")) return;

        router.delete(`${ROUTES.organizations.memberships.destroy(membership.organization.id, memberId)}?tab=${key}`, {
            only: ["membership", "flash"],
        });
    };

    const handleRoleChange = (memberId: number, newRole: "admin" | "standard") => {
        router.put(
            ROUTES.organizations.memberships.update(membership.organization.id, memberId),
            {
                role: newRole,
                tab: key,
            },
            {
                only: ["membership", "flash"],
            },
        );
    };

    return (
        <Table striped bordered hover responsive>
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {(membership.members as IOrganizationMember[]).map((member) => (
                    <tr key={member.id}>
                        <td>{member.full_name}</td>
                        <td>{member.email}</td>
                        <td className="px-3">
                            <Form.Select
                                value={member.role}
                                onChange={(e) => handleRoleChange(member.id, e.target.value as "admin" | "standard")}
                                size="sm"
                            >
                                <option value="admin">Admin</option>
                                <option value="standard">Standard</option>
                            </Form.Select>
                        </td>
                        <td>
                            <Button variant="danger" size="sm" onClick={() => handleDeleteMember(member.id)}>
                                Remove
                            </Button>
                        </td>
                    </tr>
                ))}
            </tbody>
        </Table>
    );
};
export default UserOrganizationMembership_Members;
