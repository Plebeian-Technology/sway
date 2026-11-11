// @lat: [[pipeline-runs-history-page-design#Why the list still updates itself]]

import * as React from "react";
import { usePoll } from "@inertiajs/react";
import { useEffect, useMemo } from "react";
import { PHASE_52_NON_TERMINAL_STATUSES } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { usePipelineRunSubscription } from "app/frontend/hooks/usePipelineRunSubscription";
import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { relativeTime } from "app/frontend/sway_utils/datetimes";
import type { PipelineRunSummary } from "app/frontend/types/pipelineRuns";

interface IProps {
    runs: PipelineRunSummary[];
}

// @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
const RUNS_ONLY_PROPS = ["runs"] as const;

const STATUS_TONE: Record<string, "info" | "warning" | "danger" | "success" | "neutral"> = {
    queued: "info",
    running: "info",
    fetching_bills: "info",
    fetching_law: "info",
    extracting_text: "info",
    parsing_sections: "info",
    generating_diffs: "info",
    fetching_hearings: "info",
    summarizing: "info",
    succeeded: "success",
    completed: "success",
    partial: "warning",
    cancelled: "warning",
    failed: "danger",
};

const PipelineRunsIndex: React.FC<IProps> = ({ runs }) => {
    // @lat: [[pipeline-runs-history-page-design#Why the list still updates itself]]
    const activeRun = useMemo(
        () => runs.find((r) => (PHASE_52_NON_TERMINAL_STATUSES as readonly string[]).includes(r.status)),
        [runs],
    );

    // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
    usePipelineRunSubscription(activeRun?.remote_run_id ?? null, RUNS_ONLY_PROPS);

    // @lat: [[pipeline-runs-history-page-design#Why the list still updates itself]]
    const { start: startPolling, stop: stopPolling } = usePoll(
        15000,
        { only: [...RUNS_ONLY_PROPS] },
        { autoStart: false },
    );
    useEffect(() => {
        if (activeRun) {
            startPolling();
        } else {
            stopPolling();
        }
    }, [activeRun, startPolling, stopPolling]);

    return (
        <div className="container mx-auto px-4 py-6 sm:px-6" data-testid="pipeline-runs-index">
            <Card>
                <CardHeader>
                    <CardTitle>Pipeline Run History</CardTitle>
                </CardHeader>
                <CardContent className="max-w-full overflow-hidden p-0">
                    {runs.length === 0 ? (
                        <p className="p-6 text-sm text-muted-foreground">No pipeline runs yet.</p>
                    ) : (
                        <TooltipProvider delayDuration={150}>
                            <div className="max-w-full overflow-x-auto">
                                <Table>
                                    <TableHeader>
                                        <TableRow>
                                            <TableHead className="w-16">#</TableHead>
                                            <TableHead className="w-32">Status</TableHead>
                                            <TableHead className="w-24">Kind</TableHead>
                                            <TableHead className="w-28">Bill</TableHead>
                                            <TableHead className="w-36">Started</TableHead>
                                            <TableHead className="w-36">Completed</TableHead>
                                            <TableHead className="w-28">Bills (✓/✗/tot)</TableHead>
                                            <TableHead>Failing stage</TableHead>
                                        </TableRow>
                                    </TableHeader>
                                    <TableBody>
                                        {runs.map((run) => {
                                            const tone = STATUS_TONE[run.status] ?? "neutral";
                                            return (
                                                <TableRow key={run.id} data-testid={`pipeline-run-row-${run.id}`}>
                                                    {/* @lat: [[pipeline-runs-index-only-surface#Why index precomputes bill counts]] */}
                                                    <TableCell>{run.id}</TableCell>
                                                    <TableCell>
                                                        <Badge data-tone={tone}>{run.status}</Badge>
                                                    </TableCell>
                                                    <TableCell className="text-xs">
                                                        {run.kind === "single" ? "single" : "all bills"}
                                                    </TableCell>
                                                    <TableCell className="text-xs tabular-nums">
                                                        {run.bill_external_id ?? "—"}
                                                    </TableCell>
                                                    <TableCell className="text-xs text-muted-foreground">
                                                        {run.started_at ? (
                                                            <Tooltip>
                                                                <TooltipTrigger asChild>
                                                                    <span>{relativeTime(run.started_at)}</span>
                                                                </TooltipTrigger>
                                                                <TooltipContent>{run.started_at}</TooltipContent>
                                                            </Tooltip>
                                                        ) : (
                                                            "—"
                                                        )}
                                                    </TableCell>
                                                    <TableCell className="text-xs text-muted-foreground">
                                                        {run.completed_at ? (
                                                            <Tooltip>
                                                                <TooltipTrigger asChild>
                                                                    <span>{relativeTime(run.completed_at)}</span>
                                                                </TooltipTrigger>
                                                                <TooltipContent>{run.completed_at}</TooltipContent>
                                                            </Tooltip>
                                                        ) : (
                                                            "—"
                                                        )}
                                                    </TableCell>
                                                    <TableCell className="text-xs tabular-nums">
                                                        <span className="text-emerald-600">{run.bills_succeeded}</span>
                                                        {" / "}
                                                        <span className="text-rose-600">{run.bills_failed}</span>
                                                        {" / "}
                                                        {run.bills_total}
                                                    </TableCell>
                                                    <TableCell className="text-xs text-muted-foreground">
                                                        {run.failing_stage ?? "—"}
                                                    </TableCell>
                                                </TableRow>
                                            );
                                        })}
                                    </TableBody>
                                </Table>
                            </div>
                        </TooltipProvider>
                    )}
                </CardContent>
            </Card>
        </div>
    );
};

export default PipelineRunsIndex;
