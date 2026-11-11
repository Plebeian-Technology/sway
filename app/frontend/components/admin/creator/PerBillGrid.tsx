// @lat: [[per-bill-grid-virtualization#Why only visible rows are drawn, with the current bill pinned outside that]]

import { memo, useMemo, useRef } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { TooltipProvider } from "app/frontend/components/ui/tooltip";
import { cn } from "app/frontend/lib/utils";
import type { PipelineRunBill } from "app/frontend/types/bill_creator";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { COLUMN_TEMPLATE, PINNED_ROW_CLASSES } from "app/frontend/components/admin/creator/per-bill-grid/constants";
import { GridHeaderRow } from "app/frontend/components/admin/creator/per-bill-grid/GridHeaderRow";
import { RowCells } from "app/frontend/components/admin/creator/per-bill-grid/RowCells";
import type { BillExternalIdLookup } from "app/frontend/components/admin/creator/per-bill-grid/types";

interface IProps {
    rows: PipelineRunBill[];
    currentBillExternalId: string;
    // @lat: [[per-bill-grid-virtualization#Why currentStage/stagesSucceeded/stagesTotal are props, not computed per row]]
    currentStage: string | null;
    // @lat: [[per-bill-grid-virtualization#Why runStatus is threaded down to RowCells]]
    runStatus: string | null;
    stagesSucceeded: number;
    stagesTotal: number;
    // @lat: [[per-bill-grid-virtualization#Why billIdByExternalId is optional]]
    billIdByExternalId?: BillExternalIdLookup;
}

const PerBillGridComponent: React.FC<IProps> = ({
    rows,
    currentBillExternalId,
    currentStage,
    runStatus,
    stagesSucceeded,
    stagesTotal,
    billIdByExternalId,
}) => {
    const scrollContainerRef = useRef<HTMLTableSectionElement>(null);

    // @lat: [[per-bill-grid-virtualization#Why pinnedRow is filtered out of virtualRows rather than reordered]]
    const pinnedRow = useMemo(
        () => rows.find((r) => r.bill_external_id === currentBillExternalId) ?? null,
        [rows, currentBillExternalId],
    );
    const virtualRows = useMemo(
        () => rows.filter((r) => r.bill_external_id !== currentBillExternalId),
        [rows, currentBillExternalId],
    );

    // @lat: [[per-bill-grid-virtualization#Why the React Compiler skips this component]]
    // oxlint-disable-next-line react/incompatible-library
    const rowVirtualizer = useVirtualizer({
        count: virtualRows.length,
        getScrollElement: () => scrollContainerRef.current,
        estimateSize: () => 48,
        overscan: 5,
        // @lat: [[per-bill-grid-virtualization#Why measureElement is disabled on Firefox]]
        measureElement:
            typeof window !== "undefined" && navigator.userAgent.indexOf("Firefox") === -1
                ? (element) => element?.getBoundingClientRect().height
                : undefined,
    });

    if (rows.length === 0) {
        return (
            <Card data-testid="per-bill-grid">
                <CardHeader>
                    <CardTitle>Bills in this run</CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="text-center py-8">
                        <div className="text-sm text-muted-foreground">No bills processed yet</div>
                        <div className="text-xs text-muted-foreground mt-1">
                            Bill status will appear as the run progresses.
                        </div>
                    </div>
                </CardContent>
            </Card>
        );
    }

    return (
        <Card data-testid="per-bill-grid" className="max-w-full overflow-hidden">
            <CardHeader>
                <div className="flex items-center gap-1.5">
                    <CardTitle>Bills in this run</CardTitle>
                    <FeatureInfo note="pipeline.perBillGrid" />
                </div>
            </CardHeader>
            <CardContent className="p-0">
                <div className="overflow-x-auto max-w-full" data-testid="per-bill-grid-scroll-container">
                    {/* @lat: [[per-bill-grid-virtualization#Why aria-rowcount sits on the table, and why one TooltipProvider covers every row]] */}
                    <TooltipProvider delayDuration={150}>
                        <table aria-rowcount={rows.length} className="min-w-[724px] w-full">
                            {/* @lat: [[per-bill-grid-virtualization#Why the column headings sit outside the scrolling area]] */}
                            <thead>
                                <GridHeaderRow />
                            </thead>

                            {/* @lat: [[per-bill-grid-virtualization#Why the pinned row and the first scrolling row each draw their own bottom border]] */}
                            <tbody>
                                {pinnedRow && (
                                    <tr
                                        aria-rowindex={2}
                                        data-testid="pinned-row"
                                        className={cn("grid", PINNED_ROW_CLASSES)}
                                        style={{ gridTemplateColumns: COLUMN_TEMPLATE }}
                                    >
                                        <RowCells
                                            row={pinnedRow}
                                            currentStage={currentStage}
                                            runStatus={runStatus}
                                            stagesSucceeded={stagesSucceeded}
                                            stagesTotal={stagesTotal}
                                            showActions={false}
                                            billId={billIdByExternalId?.[pinnedRow.bill_external_id]}
                                        />
                                    </tr>
                                )}
                            </tbody>

                            {/* @lat: [[per-bill-grid-virtualization#Why the scroll container's height is capped as a viewport share, not a fixed px]] */}
                            <tbody
                                ref={scrollContainerRef}
                                data-testid="virtual-scroll-container"
                                style={{
                                    minHeight: 200,
                                    maxHeight: "60vh",
                                    overflowY: "auto",
                                    overflowX: "hidden",
                                    display: "block",
                                    position: "relative",
                                }}
                            >
                                {/* @lat: [[per-bill-grid-virtualization#Why the scroll height comes from a spacer row, not a wrapper div]] */}
                                <tr
                                    aria-hidden="true"
                                    style={{ display: "block", height: `${rowVirtualizer.getTotalSize()}px` }}
                                />
                                {rowVirtualizer.getVirtualItems().map((vi) => {
                                    const row = virtualRows[vi.index];
                                    // @lat: [[per-bill-grid-virtualization#Why aria-rowindex accounts for the header and pinned row]]
                                    const rowIndexOffset = pinnedRow ? 3 : 2;
                                    return (
                                        <tr
                                            key={row.bill_external_id}
                                            aria-rowindex={vi.index + rowIndexOffset}
                                            data-index={vi.index}
                                            ref={rowVirtualizer.measureElement}
                                            className="grid border-b border-border-soft"
                                            style={{
                                                gridTemplateColumns: COLUMN_TEMPLATE,
                                                position: "absolute",
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                transform: `translateY(${vi.start}px)`,
                                            }}
                                        >
                                            <RowCells
                                                row={row}
                                                currentStage={currentStage}
                                                runStatus={runStatus}
                                                stagesSucceeded={stagesSucceeded}
                                                stagesTotal={stagesTotal}
                                                showActions={true}
                                                billId={billIdByExternalId?.[row.bill_external_id]}
                                            />
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </TooltipProvider>
                </div>
            </CardContent>
        </Card>
    );
};

// @lat: [[per-bill-grid-virtualization#Why PerBillGrid is wrapped in memo]]
const PerBillGrid = memo(PerBillGridComponent);

export default PerBillGrid;
