// @lat: [[membership-invite-accept-flow#MemberInviteForm.tsx, the current (V2) member-invite form]]

import { useForm } from "@inertiajs/react";
import { Mail } from "lucide-react";
import { useState } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";

interface IProps {
    organizationId: number;
}

const MemberInviteForm: React.FC<IProps> = ({ organizationId }) => {
    const form = useForm({ invitee_email: "" });
    const [inviteSent, setInviteSent] = useState(false);

    const handleSubmit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        // @lat: [[membership-invite-accept-flow#MemberInviteForm.tsx, the current (V2) member-invite form]]
        form.transform((data) => ({ invite: { invitee_email: data.invitee_email } }));
        form.post(`/organizations/${organizationId}/membership_invites`, {
            preserveScroll: true,
            onSuccess: () => {
                form.reset();
                setInviteSent(true);
            },
        });
    };

    return (
        <form
            onSubmit={handleSubmit}
            data-testid="org-invite-form"
            className="space-y-3 rounded-lg border-neo border-border-strong bg-card p-4"
        >
            <div className="grid gap-3 md:grid-cols-[1fr_auto] md:items-end">
                <div className="space-y-1">
                    <Label htmlFor="org-invite-email">Invitee Email</Label>
                    <Input
                        id="org-invite-email"
                        type="email"
                        value={form.data.invitee_email}
                        onChange={(e) => {
                            form.setData("invitee_email", e.target.value);
                            setInviteSent(false);
                        }}
                        placeholder="name@example.com"
                        required
                        aria-invalid={Boolean(form.errors.invitee_email)}
                        aria-describedby={form.errors.invitee_email ? "org-invite-email-error" : undefined}
                    />
                    {form.errors.invitee_email && (
                        <p id="org-invite-email-error" role="alert" className="text-sm font-semibold text-destructive">
                            {form.errors.invitee_email}
                        </p>
                    )}
                </div>
                <Button type="submit" disabled={form.processing}>
                    <Mail className="mr-1 size-4" aria-hidden />
                    Send Invite
                </Button>
            </div>
            {inviteSent && (
                <output data-testid="org-invite-success" className="text-sm font-semibold text-primary">
                    {PARITY_COPY.members.inviteSuccess}
                </output>
            )}
        </form>
    );
};

export default MemberInviteForm;
