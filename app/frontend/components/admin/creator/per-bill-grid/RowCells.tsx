// @lat: [[per-bill-grid-virtualization#Why only visible rows are drawn, with the current bill pinned outside that]]

import { memo } from "react";
import { Link } from "@inertiajs/react";
import { Tooltip, TooltipContent, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { relativeTime } from "app/frontend/sway_utils/datetimes";
import { isTerminalRunStatus } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { StatusBadge } from "app/frontend/components/admin/creator/per-bill-grid/StatusBadge";
import type { IRowCellsProps } from "app/frontend/components/admin/creator/per-bill-grid/types";

const RowCells: React.FC<IRowCellsProps> = memo(
    ({ row, currentStage, runStatus, stagesSucceeded, stagesTotal, showActions, billId }) => (
        <>
            <td className="px-3 py-2 truncate" style={{ minWidth: 240 }}>
                <Tooltip>
                    <TooltipTrigger asChild>
                        <div className="text-sm truncate">{row.title ?? row.bill_external_id}</div>
                    </TooltipTrigger>
                    <TooltipContent>{row.title ?? row.bill_external_id}</TooltipContent>
                </Tooltip>
                <div className="text-xs text-muted-foreground tabular-nums lining-nums">{row.bill_external_id}</div>
            </td>
            <td className="px-3 py-2" style={{ width: 100 }}>
                <StatusBadge status={row.status} />
            </td>
            {/* @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses#PerBillGrid's test for the finished-run Stage column]] */}
            <td className="px-3 py-2 text-xs text-muted-foreground" style={{ width: 120 }}>
                {isTerminalRunStatus(runStatus) ? "—" : (currentStage ?? "—")}
            </td>
            <td className="px-3 py-2 text-xs text-muted-foreground tabular-nums lining-nums" style={{ width: 80 }}>
                {stagesSucceeded}/{stagesTotal}
            </td>
            <td className="px-3 py-2 text-xs text-muted-foreground" style={{ width: 120 }}>
                {row.started_at ? (
                    <Tooltip>
                        <TooltipTrigger asChild>
                            <span>{relativeTime(row.started_at)}</span>
                        </TooltipTrigger>
                        <TooltipContent>{row.started_at}</TooltipContent>
                    </Tooltip>
                ) : (
                    "—"
                )}
            </td>
            <td className="px-3 py-2 text-xs" style={{ width: 64 }}>
                {showActions && billId !== undefined && (
                    <Link
                        className="inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded px-1.5 py-1 text-xs text-muted-foreground hover:underline"
                        href={`/admin/bill_creator/${billId}/pipeline?bill_id=${billId}`}
                        preserveScroll
                        data-testid="per-bill-grid-view-link"
                    >
                        View
                    </Link>
                )}
            </td>
        </>
    ),
);
RowCells.displayName = "RowCells";

export { RowCells };
export default RowCells;
