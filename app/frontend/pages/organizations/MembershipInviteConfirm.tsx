// @lat: [[membership-invite-accept-flow#MembershipInviteConfirm.tsx, the frontend confirm page]]

import { useCallback } from "react";
import { useForm } from "@inertiajs/react";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";

interface IProps {
    signed_token: string;
    organization: { id: number; name: string };
    inviter_name: string | null;
    expires_at: string | null;
}

const MembershipInviteConfirm: React.FC<IProps> = ({ signed_token, organization, inviter_name, expires_at }) => {
    const form = useForm<{ base?: string }>({});

    const handleAccept = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();
            form.post(`/organizations/${organization.id}/membership_invites/${signed_token}/accept`, {
                preserveScroll: true,
            });
        },
        [form, organization.id, signed_token],
    );

    return (
        <Card>
            <CardHeader>
                <CardTitle>Accept invitation to {organization.name}</CardTitle>
                {inviter_name && <p className="text-sm text-muted-foreground">Invited by {inviter_name}</p>}
            </CardHeader>
            <CardContent>
                <p className="mb-4">
                    By accepting, you join {organization.name} as a member.
                    {expires_at && <> This invitation expires {new Date(expires_at).toLocaleString()}.</>}
                </p>
                {form.errors.base && <p className="mb-4 text-sm text-destructive">{form.errors.base}</p>}
                <form onSubmit={handleAccept}>
                    <Button type="submit" disabled={form.processing}>
                        {form.processing ? "Accepting..." : "Accept Invitation"}
                    </Button>
                </form>
            </CardContent>
        </Card>
    );
};

export default MembershipInviteConfirm;
