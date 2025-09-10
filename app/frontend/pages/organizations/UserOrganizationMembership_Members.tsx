import { router, usePage } from "@inertiajs/react";
import { IMembership, useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
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
        router.visit(`/user_organization_memberships/${membership.id}?tab=${key}`, {
            method: "delete",
            data: { working_membership_id: memberId, tab: key },
            only: ["membership"],
            preserveState: true,
            preserveScroll: true,
        });
    };

    const handleRoleChange = (memberId: number, newRole: "admin" | "standard") => {
        router.visit(`/user_organization_memberships/${membership.id}?tab=${key}`, {
            method: "put",
            data: { working_membership_id: memberId, role: newRole, tab: key },
            only: ["membership"],
            preserveState: true,
            preserveScroll: true,
        });
    };

    return (
        <Table striped bordered hover>
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
                        <td>
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
                                Delete
                            </Button>
                        </td>
                    </tr>
                ))}
            </tbody>
        </Table>
    );
};
export default UserOrganizationMembership_Members;
