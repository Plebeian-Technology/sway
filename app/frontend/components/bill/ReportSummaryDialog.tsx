import { useForm, usePage } from "@inertiajs/react";
import { CheckCircle2, Flag, LoaderCircle } from "lucide-react";
import React, { useState } from "react";
import type { sway } from "sway";

import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Label } from "app/frontend/components/ui/label";
import { RadioGroup, RadioGroupItem } from "app/frontend/components/ui/radio-group";
import { Textarea } from "app/frontend/components/ui/textarea";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import { cn } from "@/lib/utils";

export type ReportReason = "factual_inaccuracy" | "misleading_tone" | "missing_amendment" | "other";

interface IProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    billId: number;
    billLink?: string | null;
}

interface IReportFormData {
    reason: ReportReason | "";
    details: string;
}

const REASONS: { value: ReportReason; label: string; description: string }[] = [
    {
        value: "factual_inaccuracy",
        label: "Factual inaccuracy",
        description: "Summary contains incorrect facts, wrong numbers, or misstates provisions.",
    },
    {
        value: "misleading_tone",
        label: "Misleading tone or bias",
        description: "Summary uses biased language or presents the bill in a slanted way.",
    },
    {
        value: "missing_amendment",
        label: "Missing amendment or outdated text",
        description: "The bill has been amended, substituted, or withdrawn since this summary was created.",
    },
    {
        value: "other",
        label: "Other issue",
        description: "Formatting error, truncation, or general inaccuracy.",
    },
];

const STORAGE_PREFIX = "sway:reported_bill_";

const ReportSummaryDialog: React.FC<IProps> = ({ open, onOpenChange, billId }) => {
    const { props } = usePage<sway.IPageProps>();
    const user = props.user;

    const checkAlreadyReported = (): boolean => {
        try {
            return typeof window !== "undefined" && Boolean(localStorage.getItem(`${STORAGE_PREFIX}${billId}`));
        } catch {
            return false;
        }
    };

    const [isSubmitted, setIsSubmitted] = useState(false);
    const [markedReported, setMarkedReported] = useState(false);
    const alreadyReported = markedReported || (open && checkAlreadyReported());

    const form = useForm<IReportFormData>({
        reason: "",
        details: "",
    });

    const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        form.post(ROUTES.billSummaryReports(billId), {
            preserveScroll: true,
            onSuccess: () => {
                setIsSubmitted(true);
                setMarkedReported(true);
                try {
                    localStorage.setItem(`${STORAGE_PREFIX}${billId}`, "true");
                } catch {}
            },
        });
    };

    const handleClose = () => {
        onOpenChange(false);
    };

    const isDetailsValid = form.data.details.trim().length >= 10;
    const canSubmit = Boolean(form.data.reason) && isDetailsValid && !form.processing;

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                className={cn(
                    "max-w-xl max-sm:fixed max-sm:inset-x-0 max-sm:bottom-0 max-sm:top-auto",
                    "max-sm:max-h-[92vh] max-sm:rounded-t-2xl max-sm:rounded-b-none max-sm:border-b-0 max-sm:p-5 max-sm:overflow-y-auto",
                )}
            >
                <div
                    className="mx-auto -mt-2 mb-2 h-1.5 w-12 rounded-full bg-muted-foreground/30 sm:hidden"
                    aria-hidden="true"
                />

                {alreadyReported || isSubmitted ? (
                    <div className="space-y-4 py-4 text-center" data-testid="report-confirmation-view">
                        <div className="mx-auto flex size-12 items-center justify-center rounded-full bg-vote-for/10">
                            <CheckCircle2 className="size-8 text-vote-for" aria-hidden="true" />
                        </div>
                        <DialogTitle className="text-xl font-black text-foreground">
                            {PARITY_COPY.bill.reportSubmittedTitle}
                        </DialogTitle>
                        <DialogDescription className="text-sm text-muted-foreground">
                            {alreadyReported
                                ? PARITY_COPY.bill.alreadyReportedNotice
                                : PARITY_COPY.bill.reportSubmittedMessage}
                        </DialogDescription>
                        <DialogFooter className="sm:justify-center">
                            <Button
                                type="button"
                                onClick={handleClose}
                                className="min-h-11"
                                data-testid="btn-close-report-dialog"
                            >
                                Done
                            </Button>
                        </DialogFooter>
                    </div>
                ) : (
                    <form onSubmit={handleSubmit} className="space-y-4" data-testid="report-summary-form">
                        <DialogHeader>
                            <DialogTitle className="flex items-center gap-2 text-lg font-black text-foreground">
                                <Flag className="size-5 text-muted-foreground" aria-hidden="true" />
                                {PARITY_COPY.bill.reportDialogTitle}
                            </DialogTitle>
                            <DialogDescription className="text-xs text-muted-foreground">
                                {PARITY_COPY.bill.reportDialogDescription}
                            </DialogDescription>
                        </DialogHeader>

                        <div className="space-y-2">
                            <Label className="text-xs font-black uppercase tracking-wider text-muted-foreground">
                                What is the issue? <span className="text-destructive">*</span>
                            </Label>
                            <RadioGroup
                                value={form.data.reason}
                                onValueChange={(v) => form.setData("reason", v as ReportReason)}
                                className="grid gap-2"
                            >
                                {REASONS.map((r) => (
                                    <label
                                        key={r.value}
                                        htmlFor={`reason-${r.value}`}
                                        className={cn(
                                            "flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border border-border p-3 transition",
                                            form.data.reason === r.value
                                                ? "border-primary bg-primary/5 shadow-neo-sm"
                                                : "bg-surface-2 hover:bg-accent/40",
                                        )}
                                    >
                                        <RadioGroupItem value={r.value} id={`reason-${r.value}`} className="mt-0.5" />
                                        <div className="min-w-0 flex-1">
                                            <div className="text-sm font-bold text-foreground">{r.label}</div>
                                            <div className="text-xs text-muted-foreground">{r.description}</div>
                                        </div>
                                    </label>
                                ))}
                            </RadioGroup>
                            {form.errors?.reason && (
                                <p className="text-xs font-semibold text-destructive">{form.errors?.reason}</p>
                            )}
                        </div>

                        <div className="space-y-1.5">
                            <div className="flex items-center justify-between">
                                <Label
                                    htmlFor="report-details"
                                    className="text-xs font-black uppercase tracking-wider text-muted-foreground"
                                >
                                    Details <span className="text-destructive">*</span>
                                </Label>
                                <span
                                    className={cn(
                                        "text-xs tabular-nums",
                                        form.data.details.length > 2000
                                            ? "text-destructive font-bold"
                                            : "text-muted-foreground",
                                    )}
                                >
                                    {form.data.details.length}/2000
                                </span>
                            </div>
                            <Textarea
                                id="report-details"
                                rows={4}
                                maxLength={2000}
                                placeholder="Explain what is incorrect or misleading, and what the bill actually specifies…"
                                value={form.data.details}
                                onChange={(e) => form.setData("details", e.target.value)}
                                className="text-sm"
                                required
                            />
                            {form.errors?.details && (
                                <p className="text-xs font-semibold text-destructive">{form.errors?.details}</p>
                            )}
                            <p className="text-[11px] text-muted-foreground">
                                Minimum 10 characters. Please cite sections or specific wording if possible.
                            </p>
                        </div>

                        {!user && (
                            <p className="text-xs text-muted-foreground/80 italic">
                                Submitting as guest. Your report will be reviewed by editors.
                            </p>
                        )}

                        <DialogFooter className="gap-2 sm:gap-0">
                            <DialogClose asChild>
                                <Button type="button" variant="outline" onClick={handleClose} className="min-h-11">
                                    Cancel
                                </Button>
                            </DialogClose>
                            <Button
                                type="submit"
                                disabled={!canSubmit}
                                className="min-h-11 cursor-pointer"
                                data-testid="btn-submit-report"
                            >
                                {form.processing ? (
                                    <>
                                        <LoaderCircle className="size-4 animate-spin" aria-hidden="true" />
                                        Submitting…
                                    </>
                                ) : (
                                    "Submit Report"
                                )}
                            </Button>
                        </DialogFooter>
                    </form>
                )}
            </DialogContent>
        </Dialog>
    );
};

export default ReportSummaryDialog;
