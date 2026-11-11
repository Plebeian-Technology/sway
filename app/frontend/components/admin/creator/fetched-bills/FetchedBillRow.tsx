import { Link } from "@inertiajs/react";
import { memo } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { TableCell, TableRow } from "app/frontend/components/ui/table";
import { relativeTime } from "app/frontend/sway_utils/datetimes";
import type { FetchedBillsRow } from "app/frontend/types/bill_creator";
import { freshnessLabel, freshnessTone } from "app/frontend/components/admin/creator/fetched-bills/freshness";

interface IProps {
    row: FetchedBillsRow;
}

const FetchedBillRow: React.FC<IProps> = ({ row }) => {
    const tone = freshnessTone(row.fetched_at);
    return (
        <TableRow data-testid={`fetched-bill-row-${row.external_id}`}>
            <TableCell className="font-mono text-xs tabular-nums">{row.external_id}</TableCell>
            <TableCell className="text-sm">
                {row.bill_row_exists && row.bill_id !== null ? (
                    <Link
                        href={`/admin/bill_creator/${row.bill_id}/pipeline?bill_id=${row.bill_id}`}
                        className="text-primary hover:underline"
                        data-testid={`fetched-bill-link-${row.external_id}`}
                    >
                        {row.title ?? row.external_id}
                    </Link>
                ) : (
                    <span
                        className="italic text-muted-foreground"
                        data-testid={`fetched-bill-orphan-${row.external_id}`}
                    >
                        (orphan on disk)
                    </span>
                )}
            </TableCell>
            <TableCell className="text-xs tabular-nums">
                <Badge data-tone={tone} title={row.fetched_at}>
                    {freshnessLabel(tone)}
                </Badge>
                <span className="ml-2 text-muted-foreground">{relativeTime(row.fetched_at)}</span>
            </TableCell>
            <TableCell className="text-xs">{row.pdf_present ? "✓" : "—"}</TableCell>
        </TableRow>
    );
};

export default memo(FetchedBillRow);
