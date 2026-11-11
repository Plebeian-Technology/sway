import type { PipelineRunBillStatus } from "app/frontend/types/bill_creator";

export const STATUS_TONE: Record<
    PipelineRunBillStatus,
    { variant: "solid" | "stamp"; tone: "neutral" | "info" | "success" | "danger" }
> = {
    pending: { variant: "solid", tone: "neutral" },
    running: { variant: "stamp", tone: "info" },
    succeeded: { variant: "stamp", tone: "success" },
    failed: { variant: "stamp", tone: "danger" },
    skipped: { variant: "solid", tone: "neutral" },
};

export const DEFAULT_STATUS_TONE = { variant: "solid", tone: "neutral" } as const;

export const COLUMN_TEMPLATE = "minmax(240px,1fr) 100px 120px 80px 120px 64px";

export const PINNED_ROW_CLASSES =
    "ring-[length:var(--neo-border-width)] ring-inset ring-primary bg-primary/8 border-b-neo border-border-soft";
