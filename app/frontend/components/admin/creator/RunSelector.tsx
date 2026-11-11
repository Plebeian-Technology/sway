// @lat: [[run-selector-mechanics#Why picking a run sets ?run_id=]]

import { router } from "@inertiajs/react";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import type { IRecentPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";
import { PHASE_52_STAGE_STATUS_LABELS } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { failureAge } from "app/frontend/sway_utils/failureTiming";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

// @lat: [[run-selector-mechanics#Why RUN_SELECTOR_ONLY_PROPS asks for exactly these props]]
const RUN_SELECTOR_ONLY_PROPS = [
    "legislation_pipeline_run",
    "active_legislation_pipeline_run",
    "recent_pipeline_runs",
    "stale_pipeline_run_count",
    "orphan_pipeline_run_count",
];

// @lat: [[run-selector-mechanics#Why STATUS_GLYPH reuses the shared per-stage label map]]
const STATUS_GLYPH: Record<string, string> = {
    succeeded: "✓ succeeded",
    completed: "✓ completed",
    failed: "✗ failed",
    partial: "◑ partial",
    cancelled: "⊘ cancelled",
    queued: "queued",
    running: "● running",
    ...PHASE_52_STAGE_STATUS_LABELS,
};

function runLabel(run: IRecentPipelineRun): string {
    const age = run.status === "failed" ? failureAge(run.completed_at) : null;
    const status = (STATUS_GLYPH[run.status ?? ""] ?? run.status ?? "—") + (age ? ` ${age}` : "");
    const scope = run.kind === "single" ? (run.bill_external_id ?? "single bill") : "all bills";
    const when = run.created_at ? formatDateTime(run.created_at) : "";
    return `Run #${run.id} · ${status} · ${scope}${when ? ` · ${when}` : ""}`;
}

interface IProps {
    runs: IRecentPipelineRun[];
    currentRunId: number | null;
}

const RunSelector: React.FC<IProps> = ({ runs, currentRunId }) => {
    if (!runs.length) return null;

    // @lat: [[run-selector-mechanics#Why pinned checks the address, not just currentRunId]]
    const pinned = typeof window !== "undefined" && new URLSearchParams(window.location.search).has("run_id");

    const handleChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
        const value = event.target.value;
        const search = new URLSearchParams(window.location.search);
        if (value) {
            search.set("run_id", value);
        } else {
            // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
            setQueryParamCleared(search, "run_id");
        }
        const query = search.toString();
        router.get(`${window.location.pathname}${query ? `?${query}` : ""}`, undefined, {
            only: RUN_SELECTOR_ONLY_PROPS,
            preserveScroll: true,
            preserveState: true,
        });
    };

    return (
        <div className="flex w-full flex-wrap items-center gap-2 sm:flex-nowrap">
            <label className="flex w-full min-w-0 flex-1 flex-wrap items-center gap-2 text-sm sm:flex-nowrap">
                <span className="font-medium whitespace-nowrap">Viewing run</span>
                <select
                    className="min-h-[44px] min-w-0 w-full flex-1 rounded-lg border-2 border-neo bg-card px-3 py-2 text-sm sm:w-auto"
                    value={pinned && currentRunId ? String(currentRunId) : ""}
                    onChange={handleChange}
                    data-testid="run-selector"
                >
                    <option value="">Latest run (auto)</option>
                    {runs.map((run) => (
                        <option key={run.id} value={String(run.id)}>
                            {runLabel(run)}
                        </option>
                    ))}
                </select>
            </label>
            <FeatureInfo note="pipeline.runSelector" className="shrink-0" />
        </div>
    );
};

export default RunSelector;
