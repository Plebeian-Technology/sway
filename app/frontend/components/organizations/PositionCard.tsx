// @lat: [[organizations-v2-list-cards#PositionCard.tsx, the current (V2) position card]]

import { router } from "@inertiajs/react";
import { Lock, Pencil, Trash2 } from "lucide-react";
import { useState } from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Textarea } from "app/frontend/components/ui/textarea";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { ROUTES } from "app/frontend/sway_constants";
import { supportTone } from "app/frontend/sway_utils/support";
import type { IPositionWithBill } from "app/frontend/hooks/users/useUserOrganizationMembership";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import BillRowLink from "app/frontend/components/bill/BillRowLink";

interface IProps {
    position: IPositionWithBill;
    organizationId: number;
    isAdmin: boolean;
}

const PositionCard: React.FC<IProps> = ({ position, organizationId, isAdmin }) => {
    const [isEditing, setIsEditing] = useState(false);
    const [support, setSupport] = useState<string>(position.support);
    const [summary, setSummary] = useState<string>(position.summary ?? "");
    const confirm = useConfirm();

    const isLocked = Boolean(position.locked);
    const billId = position.bill?.id ?? position.bill_id;

    const handleSave = () => {
        if (!isEditing) return;
        router.put(
            ROUTES.organizations.positions.update(organizationId, position.id),
            { support, summary },
            { preserveScroll: true },
        );
        setIsEditing(false);
    };

    const handleDelete = async () => {
        const confirmed = await confirm({
            title: "Delete position?",
            description: "This removes the organization's recorded position on this bill.",
            confirmLabel: "Delete",
            tone: "destructive",
        });
        if (!confirmed) return;
        router.delete(ROUTES.organizations.positions.destroy(organizationId, position.id), {
            preserveScroll: true,
        });
    };

    return (
        <Card>
            <CardHeader className="flex flex-wrap items-start gap-2">
                <CardTitle className="flex-1 text-base leading-snug">
                    {position.bill ? (
                        <BillRowLink billId={billId} className="text-foreground underline-offset-4 hover:underline">
                            <span className="font-semibold">
                                {position.bill.external_id} - {position.bill.title}
                            </span>
                        </BillRowLink>
                    ) : (
                        <span>{`Unknown Bill with Position ID ${position.id}`}</span>
                    )}
                </CardTitle>
                <div className="flex items-center gap-2">
                    <Badge variant="stamp" tone={supportTone(position.support)}>
                        {position.support}
                    </Badge>
                    {isLocked && (
                        <TooltipProvider>
                            <Tooltip>
                                <TooltipTrigger asChild>
                                    <span
                                        className="inline-flex items-center gap-1 rounded-lg bg-muted px-2 py-1 text-xs font-semibold uppercase tracking-widest ring-[length:var(--neo-border-width)] ring-inset"
                                        aria-label="Locked"
                                    >
                                        <Lock className="size-3" aria-hidden />
                                        Locked
                                    </span>
                                </TooltipTrigger>
                                <TooltipContent>Position is approved. Submit a pending change to edit.</TooltipContent>
                            </Tooltip>
                        </TooltipProvider>
                    )}
                </div>
            </CardHeader>
            <CardContent className="space-y-3">
                {isEditing ? (
                    <>
                        <div className="space-y-1">
                            <label
                                className="text-xs font-semibold uppercase tracking-wide text-muted-foreground"
                                htmlFor={`support-${position.id}`}
                            >
                                Support
                            </label>
                            <Select value={support} onValueChange={setSupport}>
                                <SelectTrigger id={`support-${position.id}`} className="w-full">
                                    <SelectValue placeholder="Select support" />
                                </SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="FOR">Support: FOR</SelectItem>
                                    <SelectItem value="AGAINST">Support: AGAINST</SelectItem>
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-1">
                            <label
                                className="text-xs font-semibold uppercase tracking-wide text-muted-foreground"
                                htmlFor={`summary-${position.id}`}
                            >
                                Summary
                            </label>
                            <Textarea
                                id={`summary-${position.id}`}
                                rows={8}
                                value={summary}
                                onChange={(e) => setSummary(e.target.value)}
                            />
                        </div>
                    </>
                ) : (
                    <OrgPositionSummary
                        summary={position.summary}
                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                        className="text-sm"
                    />
                )}
                {isAdmin && (
                    <div className="flex flex-wrap items-center justify-between gap-2 pt-2">
                        {isEditing ? (
                            <>
                                <Button variant="outline" onClick={() => setIsEditing(false)}>
                                    Cancel
                                </Button>
                                <Button onClick={handleSave}>Save Changes</Button>
                            </>
                        ) : (
                            <>
                                <Button
                                    variant="outline"
                                    // @lat: [[position-card-edit-field-snapshot-staleness#Why PositionCard reads props at Edit-click time, not at mount]]
                                    onClick={() => {
                                        setSupport(position.support);
                                        setSummary(position.summary ?? "");
                                        setIsEditing(true);
                                    }}
                                    disabled={isLocked}
                                >
                                    <Pencil className="mr-1 size-4" aria-hidden />
                                    Edit
                                </Button>
                                <Button variant="destructive" onClick={handleDelete}>
                                    <Trash2 className="mr-1 size-4" aria-hidden />
                                    Delete
                                </Button>
                            </>
                        )}
                    </div>
                )}
            </CardContent>
        </Card>
    );
};

export default PositionCard;
