// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
import React from "react";
import { Text, View } from "react-native";

import { parseTime, relativeTime } from "../../../utils/runTime";
import CollapsibleSection from "./CollapsibleSection";

interface PipelineRunBill {
    bill_external_id: string;
    title: string | null;
    status: string;
    started_at: string | null;
}

export interface PerBillGridRun {
    kind: "single" | "all_bills";
    status: string | null;
    current_stage: string | null;
    pipeline_run_stages?: { status: string }[];
    pipeline_run_bills?: PipelineRunBill[];
}

interface PerBillGridSectionProps {
    run: PerBillGridRun | null;
    currentBillExternalId: string;
}

const TERMINAL_RUN_STATUSES = ["completed", "succeeded", "partial", "failed", "cancelled"];

const STATUS_TONES: Record<string, string> = {
    running: "text-accent-light dark:text-accent-dark",
    succeeded: "text-success-light dark:text-success-dark",
    failed: "text-destructive-light dark:text-destructive-dark",
};
const DEFAULT_STATUS_TONE = "text-muted-foreground-light dark:text-muted-foreground-dark";

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";

const startedText = (iso: string | null) => {
    const date = parseTime(iso);
    return date ? relativeTime(date) : "—";
};

const PerBillGridSection: React.FC<PerBillGridSectionProps> = ({ run, currentBillExternalId }) => {
    if (run?.kind !== "all_bills") return null;

    const bills = run.pipeline_run_bills ?? [];
    const stages = run.pipeline_run_stages ?? [];
    const stagesSucceeded = stages.filter((stage) => stage.status === "succeeded").length;
    const stageText = TERMINAL_RUN_STATUSES.includes(run.status ?? "") ? "—" : (run.current_stage ?? "—");
    const orderedBills = [
        ...bills.filter((bill) => bill.bill_external_id === currentBillExternalId),
        ...bills.filter((bill) => bill.bill_external_id !== currentBillExternalId),
    ];

    return (
        <CollapsibleSection testID="admin-per-bill-grid" title="Bills in this run">
            {orderedBills.length === 0 ? (
                <View className="gap-1">
                    <Text className={labelText}>No bills processed yet</Text>
                    <Text className={mutedText}>Bill status will appear as the run progresses.</Text>
                </View>
            ) : (
                orderedBills.map((bill) => (
                    <View
                        key={bill.bill_external_id}
                        testID={`admin-per-bill-grid-row-${bill.bill_external_id}`}
                        className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1"
                    >
                        {bill.bill_external_id === currentBillExternalId ? (
                            <Text className={mutedText}>This bill</Text>
                        ) : null}
                        <Text className={labelText}>{bill.title ?? bill.bill_external_id}</Text>
                        <Text className={mutedText}>{bill.bill_external_id}</Text>
                        <Text
                            className={`text-xs font-open-sans-semibold ${STATUS_TONES[bill.status] ?? DEFAULT_STATUS_TONE}`}
                        >
                            {bill.status}
                        </Text>
                        <Text className={mutedText}>Stage {stageText}</Text>
                        <Text className={mutedText}>
                            {stagesSucceeded}/{stages.length} stages
                        </Text>
                        <Text className={mutedText}>Started {startedText(bill.started_at)}</Text>
                    </View>
                ))
            )}
        </CollapsibleSection>
    );
};

export default PerBillGridSection;
