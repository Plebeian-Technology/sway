// @lat: [[organizations-memberships-controller-notes#The membership detail page]]

import { router, usePage } from "@inertiajs/react";
import { Trash2 } from "lucide-react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import MemberInviteForm from "app/frontend/components/organizations/MemberInviteForm";
import type { IMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";

interface IProps {
    membership: IMembership;
    isAdmin: boolean;
}

interface IPageProps {
    tab?: string;
    [key: string]: unknown;
}

const MembersList: React.FC<IProps> = ({ membership, isAdmin }) => {
    const key = usePage<IPageProps>().props.tab || "positions";
    const confirm = useConfirm();

    const handleDeleteMember = async (memberId: number) => {
        const confirmed = await confirm({
            title: "Remove member?",
            description: "They will lose access to this organization.",
            confirmLabel: "Remove",
            tone: "destructive",
        });
        if (!confirmed) return;
        router.delete(
            `${ROUTES.organizations.memberships.destroy(membership.organization.id, memberId)}?org_tab=${key}`,
            {
                only: ["membership", "flash"],
                preserveScroll: true,
            },
        );
    };

    const handleRoleChange = (memberId: number, newRole: "admin" | "standard") => {
        router.put(
            ROUTES.organizations.memberships.update(membership.organization.id, memberId),
            { role: newRole, org_tab: key },
            { only: ["membership", "flash"], preserveScroll: true },
        );
    };

    const members = membership.members ?? [];

    return (
        <div className="space-y-4">
            {isAdmin && <MemberInviteForm organizationId={membership.organization.id} />}
            <div className="overflow-hidden rounded-lg border-neo border-border-strong">
                <Table className="text-sm">
                    <TableHeader className="bg-muted text-xs font-semibold uppercase tracking-wide">
                        <TableRow>
                            <TableHead>Name</TableHead>
                            <TableHead>Email</TableHead>
                            <TableHead>Role</TableHead>
                            {isAdmin && <TableHead className="text-right">Actions</TableHead>}
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {members.length === 0 ? (
                            <TableRow>
                                <TableCell
                                    colSpan={isAdmin ? 4 : 3}
                                    className="px-3 py-4 text-center text-sm text-muted-foreground"
                                >
                                    No members yet.
                                </TableCell>
                            </TableRow>
                        ) : (
                            members.map((member) => (
                                <TableRow key={member.id}>
                                    <TableCell className="font-medium">{member.full_name}</TableCell>
                                    <TableCell className="text-muted-foreground">{member.email}</TableCell>
                                    <TableCell>
                                        {isAdmin ? (
                                            <Select
                                                value={member.role}
                                                onValueChange={(v) =>
                                                    handleRoleChange(member.id, v as "admin" | "standard")
                                                }
                                            >
                                                <SelectTrigger className="h-8 w-32">
                                                    <SelectValue />
                                                </SelectTrigger>
                                                <SelectContent>
                                                    <SelectItem value="admin">Admin</SelectItem>
                                                    <SelectItem value="standard">Standard</SelectItem>
                                                </SelectContent>
                                            </Select>
                                        ) : (
                                            <Badge
                                                variant="stamp"
                                                tone={member.role === "admin" ? "primary" : "neutral"}
                                            >
                                                {member.role}
                                            </Badge>
                                        )}
                                    </TableCell>
                                    {isAdmin && (
                                        <TableCell className="text-right">
                                            <Button
                                                variant="destructive"
                                                size="sm"
                                                onClick={() => handleDeleteMember(member.id)}
                                            >
                                                <Trash2 className="mr-1 size-3" aria-hidden />
                                                Remove
                                            </Button>
                                        </TableCell>
                                    )}
                                </TableRow>
                            ))
                        )}
                    </TableBody>
                </Table>
            </div>
        </div>
    );
};

export default MembersList;
