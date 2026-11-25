// @lat: [[mobile-bill-creator#Sections#The run selector section]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { exactTime, parseTime, relativeTime } from "../../../utils/runTime";
import { Pressable } from "../../ui/Pressable";

export interface RecentPipelineRun {
    id: number;
    status: string | null;
    kind: "single" | "all_bills";
    bill_external_id: string | null;
    created_at: string | null;
    completed_at: string | null;
}

interface RunSelectorSectionProps {
    runs: RecentPipelineRun[];
    currentRunId: number | null;
    pinned: boolean;
    onPick: (runId: number | null) => void;
}

const STATUS_GLYPHS: Record<string, string> = {
    succeeded: "✓ succeeded",
    completed: "✓ completed",
    failed: "✗ failed",
    partial: "◑ partial",
    cancelled: "⊘ cancelled",
    queued: "queued",
    running: "● running",
    fetching_bills: "Fetching bills",
    fetching_law: "Fetching law",
    extracting_text: "Extracting text",
    parsing_sections: "Parsing sections",
    generating_diffs: "Generating diffs",
    fetching_hearings: "Fetching hearings",
    cleaning_testimony: "Cleaning testimony",
    summarizing: "Summarizing",
    awaiting_summary_batch: "Awaiting summary batch",
};

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";

const runLabel = (run: RecentPipelineRun) => {
    const completed = run.status === "failed" ? parseTime(run.completed_at) : null;
    const age = completed ? ` ${relativeTime(completed)}` : "";
    const status = (STATUS_GLYPHS[run.status ?? ""] ?? run.status ?? "—") + age;
    const scope = run.kind === "single" ? (run.bill_external_id ?? "single bill") : "all bills";
    const when = exactTime(run.created_at);
    return `Run #${run.id} · ${status} · ${scope}${when ? ` · ${when}` : ""}`;
};

const RunSelectorSection: React.FC<RunSelectorSectionProps> = ({ runs, currentRunId, pinned, onPick }) => {
    const [open, setOpen] = useState(false);
    if (runs.length === 0) return null;

    const pickedRun = pinned ? runs.find((run) => run.id === currentRunId) : undefined;
    const pick = (runId: number | null) => {
        setOpen(false);
        onPick(runId);
    };

    return (
        <View testID="admin-run-selector" className="px-4 mt-6 gap-2">
            <Text className={labelText}>Viewing run</Text>
            <Pressable
                testID="admin-run-selector-toggle"
                variant="outline"
                accessibilityState={{ expanded: open }}
                onPress={() => setOpen(!open)}
            >
                <Text testID="admin-run-selector-current" className={labelText}>
                    {pickedRun ? runLabel(pickedRun) : "Latest run (auto)"}
                </Text>
            </Pressable>
            {open ? (
                <View className="gap-1">
                    <Pressable
                        testID="admin-run-selector-option-latest"
                        variant="ghost"
                        accessibilityRole="radio"
                        accessibilityState={{ selected: !pinned }}
                        onPress={() => pick(null)}
                        className="items-start px-0"
                    >
                        <Text className={labelText}>Latest run (auto)</Text>
                    </Pressable>
                    {runs.map((run) => (
                        <Pressable
                            key={run.id}
                            testID={`admin-run-selector-option-${run.id}`}
                            variant="ghost"
                            accessibilityRole="radio"
                            accessibilityState={{ selected: pinned && run.id === currentRunId }}
                            onPress={() => pick(run.id)}
                            className="items-start px-0"
                        >
                            <Text className={mutedText}>{runLabel(run)}</Text>
                        </Pressable>
                    ))}
                </View>
            ) : null}
        </View>
    );
};

export default RunSelectorSection;
