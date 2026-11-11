import { router } from "@inertiajs/react";
import { useEffect, useRef, useState } from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import BillRowLink from "app/frontend/components/bill/BillRowLink";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { renderCharDiff } from "app/frontend/sway_utils/diffToTailwind";
import type { IMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { notify } from "app/frontend/sway_utils";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";
import { supportTone } from "app/frontend/sway_utils/support";

type PendingChange = IMembership["pending_changes"][number];

interface IProps {
    change: PendingChange;
    membership: IMembership;
    isAdmin: boolean;
    isFocused?: boolean;
}

const PendingChangeCard: React.FC<IProps> = ({ change, membership, isAdmin, isFocused }) => {
    const ref = useRef<HTMLDivElement | null>(null);

    useEffect(() => {
        if (isFocused && ref.current) {
            ref.current.scrollIntoView({ behavior: "smooth", block: "start" });
        }
    }, [isFocused]);

    const position = (membership.positions ?? []).find((p) => p.id === change.organization_bill_position_id);

    // @lat: [[pending-change-card-frontend-design#Why handleApproval/handleReject guard against double-submitting]]
    const [submitting, setSubmitting] = useState(false);

    const handleApproval = () => {
        if (change.approved_by_id || !isAdmin || submitting) {
            notify({
                level: "error",
                title: "Changes can only be approved by an organization admin.",
            });
            return;
        }
        setSubmitting(true);
        router.put(`/organizations/${membership.organization.id}/position_changes/${change.id}`, undefined, {
            preserveScroll: true,
            onFinish: () => setSubmitting(false),
        });
    };

    // @lat: [[pending-change-card-frontend-design#Why IPendingChange.status is optional]]
    const approved = change.status === "approved" || Boolean(change.approved_by_id);
    const rejected = change.status === "rejected" || Boolean(change.rejected_by_id);
    const finalized = approved || rejected;
    const approveLabel = approved ? "Approved" : isAdmin ? "Approve Change" : "Pending Approval";

    const [showRejectDialog, setShowRejectDialog] = useState(false);

    // @lat: [[pending-change-card-frontend-design#Why IPendingChange.status is optional]]
    const handleReject = () => {
        if (finalized || !isAdmin || submitting) {
            notify({
                level: "error",
                title: "Changes can only be rejected by an organization admin.",
            });
            return;
        }
        setSubmitting(true);
        setShowRejectDialog(false);
        router.delete(`/organizations/${membership.organization.id}/position_changes/${change.id}`, {
            preserveScroll: true,
            onFinish: () => setSubmitting(false),
        });
    };

    return (
        <div ref={ref}>
            <Card>
                <CardHeader>
                    <CardTitle className="text-base leading-snug">
                        {position?.bill ? (
                            <BillRowLink
                                billId={position.bill.id}
                                className="text-foreground underline-offset-4 hover:underline"
                            >
                                <span className="font-semibold">
                                    {position.bill.external_id} - {position.bill.title}
                                </span>
                            </BillRowLink>
                        ) : (
                            <span>{`Unknown Bill with Position ID ${change.organization_bill_position_id}`}</span>
                        )}
                    </CardTitle>
                </CardHeader>
                <CardContent className="space-y-4 text-sm">
                    <div className="flex flex-wrap items-center gap-3">
                        <div className="flex items-center gap-2">
                            <span className="text-xs uppercase tracking-wide text-muted-foreground">Previous</span>
                            <Badge variant="stamp" tone={supportTone(change.previous_support)}>
                                {change.previous_support}
                            </Badge>
                        </div>
                        <div className="flex items-center gap-2">
                            <span className="text-xs uppercase tracking-wide text-muted-foreground">New</span>
                            <Badge variant="stamp" tone={supportTone(change.new_support)}>
                                {change.new_support}
                            </Badge>
                        </div>
                    </div>
                    <div className="space-y-1">
                        <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                            Diff of Changes
                        </div>
                        <div className="whitespace-pre-wrap rounded-lg border-neo border-border-strong bg-card p-3">
                            {renderCharDiff(change.previous_summary, change.new_summary)}
                        </div>
                    </div>
                    <div className="grid gap-3 md:grid-cols-2">
                        <div className="space-y-1">
                            <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                New Summary
                            </div>
                            <p className="whitespace-pre-wrap">{change.new_summary}</p>
                        </div>
                        <div className="space-y-1">
                            <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                Previous Summary
                            </div>
                            <p className="whitespace-pre-wrap">{change.previous_summary}</p>
                        </div>
                    </div>
                </CardContent>
                <CardFooter className="flex flex-wrap items-center justify-between gap-2">
                    <div className="text-xs text-muted-foreground">
                        <span className="uppercase tracking-wide">Created </span>
                        <span className="tabular-nums lining-nums">{formatDateTime(change.created_at)}</span>
                    </div>
                    {/* @lat: [[pending-change-card-frontend-design#Why IPendingChange.status is optional]] */}
                    <div className="flex gap-2">
                        {isAdmin && !finalized ? (
                            <Button
                                variant="destructive"
                                onClick={() => setShowRejectDialog(true)}
                                disabled={submitting}
                                aria-label={PARITY_COPY.pendingChanges.rejectConfirmAction}
                            >
                                {PARITY_COPY.pendingChanges.rejectLabel}
                            </Button>
                        ) : null}
                        <Button
                            onClick={handleApproval}
                            disabled={approved || !isAdmin || submitting}
                            variant={approved || !isAdmin ? "secondary" : "default"}
                        >
                            {approveLabel}
                        </Button>
                    </div>
                </CardFooter>
            </Card>
            <Dialog open={showRejectDialog} onOpenChange={setShowRejectDialog}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>{PARITY_COPY.pendingChanges.rejectConfirmTitle}</DialogTitle>
                        <DialogDescription>{PARITY_COPY.pendingChanges.rejectConfirmBody}</DialogDescription>
                    </DialogHeader>
                    <DialogFooter>
                        <Button variant="outline" onClick={() => setShowRejectDialog(false)}>
                            Cancel
                        </Button>
                        <Button variant="destructive" onClick={handleReject} disabled={submitting}>
                            {PARITY_COPY.pendingChanges.rejectConfirmAction}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </div>
    );
};

export default PendingChangeCard;
