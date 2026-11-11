import React from "react";
import { ShieldAlert } from "lucide-react";

import { Badge } from "app/frontend/components/ui/badge";
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { IHistoricalRepairModalProps } from "app/frontend/types/legislators";

// @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Historical repair explanations]]
// @lat: [[legislator-history-serialization#Why historical score corrections are embedded directly in term payloads]]
const HistoricalRepairModal: React.FC<IHistoricalRepairModalProps> = ({
    explanation,
    term,
    legislator,
    open,
    onOpenChange,
}) => {
    const formattedDelta =
        explanation.delta !== null && explanation.delta !== 0
            ? explanation.delta > 0
                ? `+${explanation.delta}`
                : `${explanation.delta}`
            : null;

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                showCloseButton={false}
                data-testid="historical-repair-modal"
                className="max-w-lg border-neo border-border-strong bg-card p-6 shadow-neo"
            >
                <DialogHeader className="gap-2 text-left">
                    <div className="flex flex-wrap items-center gap-2">
                        <ShieldAlert className="size-5 text-warning" aria-hidden="true" />
                        <Badge variant="stamp" tone="warning">
                            Authorized Audit
                        </Badge>
                        {formattedDelta && (
                            <Badge variant="solid" tone="info">
                                Delta: {formattedDelta}
                            </Badge>
                        )}
                    </div>
                    <DialogTitle className="text-xl font-black text-foreground">{explanation.title}</DialogTitle>
                    <DialogDescription className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                        {term.session_label} · {legislator.full_name}
                    </DialogDescription>
                </DialogHeader>

                <div className="space-y-4 py-2">
                    <div className="rounded-xl border border-border-strong bg-surface-2 p-4 text-sm leading-relaxed text-foreground whitespace-pre-line">
                        {explanation.body}
                    </div>

                    <div className="space-y-1 rounded-lg bg-surface-3 p-3 text-xs text-muted-foreground">
                        <p>
                            <span className="font-bold text-foreground">Audit Provenance: </span>
                            This score adjustment was authorized through Sway's administrative repair preview and
                            verified against official service records.
                        </p>
                        <p className="font-mono text-[11px] text-muted-foreground/80">
                            Score Reference: {explanation.score_type}
                        </p>
                    </div>
                </div>

                <DialogFooter>
                    <DialogClose asChild>
                        <button
                            type="button"
                            className="inline-flex h-9 cursor-pointer items-center justify-center rounded-xl border-neo border-border-strong bg-surface-2 px-4 text-sm font-semibold text-foreground shadow-neo transition"
                        >
                            Close
                        </button>
                    </DialogClose>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default HistoricalRepairModal;
