import { useMemo, useState } from "react";
import { Button } from "app/frontend/components/ui/button";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import type { FetchedBillsRow } from "app/frontend/types/bill_creator";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import FetchedBillRow from "app/frontend/components/admin/creator/fetched-bills/FetchedBillRow";
import FetchedBillsFilters from "app/frontend/components/admin/creator/fetched-bills/FetchedBillsFilters";
import { freshnessTone, type FreshnessFilter } from "app/frontend/components/admin/creator/fetched-bills/freshness";

interface IProps {
    rows: FetchedBillsRow[];
}

// @lat: [[pipeline-llm-only-props-membership#Why FetchedBillsPanel is refreshed through this same list]]
const FetchedBillsPanel: React.FC<IProps> = ({ rows }) => {
    const [query, setQuery] = useState<string>("");
    const [filter, setFilter] = useState<FreshnessFilter>("all");

    const filteredRows = useMemo(() => {
        const q = query.trim().toLowerCase();
        return rows.filter((row) => {
            if (filter !== "all" && freshnessTone(row.fetched_at) !== filter) return false;
            if (q.length === 0) return true;
            const idMatch = row.external_id.toLowerCase().includes(q);
            const titleMatch = row.title?.toLowerCase().includes(q) ?? false;
            return idMatch || titleMatch;
        });
    }, [rows, query, filter]);

    const isFiltering = query.trim().length > 0 || filter !== "all";
    const clearFilters = () => {
        setQuery("");
        setFilter("all");
    };

    if (rows.length === 0) {
        return (
            <section className="flex flex-col gap-3" data-testid="fetched-bills-panel">
                <p className="text-sm italic text-muted-foreground">
                    No bill artifacts on disk yet. Run the fetch-bills stage to populate.
                </p>
            </section>
        );
    }

    return (
        <section className="flex flex-col gap-3" data-testid="fetched-bills-panel">
            <header className="flex items-center justify-end gap-1.5">
                <span className="text-xs text-muted-foreground tabular-nums" data-testid="fetched-bills-count">
                    {isFiltering
                        ? `${filteredRows.length} of ${rows.length} bills`
                        : `${rows.length} ${rows.length === 1 ? "bill" : "bills"}`}
                </span>
                <FeatureInfo note="pipeline.fetchedBills" />
            </header>
            <div className="border-b-neo border-border-soft" />

            <FetchedBillsFilters query={query} filter={filter} onQueryChange={setQuery} onFilterChange={setFilter} />

            {filteredRows.length === 0 ? (
                <div
                    className="flex flex-col items-start gap-2 rounded-md border border-border-soft p-3 text-sm italic text-muted-foreground"
                    data-testid="fetched-bills-empty-filtered"
                >
                    <span>No bills match.</span>
                    <Button
                        type="button"
                        size="xs"
                        variant="outline"
                        onClick={clearFilters}
                        data-testid="fetched-bills-clear"
                        className="min-h-[44px] sm:min-h-0"
                    >
                        Clear filters
                    </Button>
                </div>
            ) : (
                <div
                    className="max-h-[760px] max-w-full overflow-auto rounded-md border border-border-soft"
                    data-testid="fetched-bills-scroll"
                >
                    <Table>
                        <TableHeader className="sticky top-0 z-10 bg-card">
                            <TableRow>
                                <TableHead className="w-36">External ID</TableHead>
                                <TableHead>Bill</TableHead>
                                <TableHead className="w-40">Fetched</TableHead>
                                <TableHead className="w-16">PDF</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {filteredRows.map((row) => (
                                <FetchedBillRow key={row.external_id} row={row} />
                            ))}
                        </TableBody>
                    </Table>
                </div>
            )}
        </section>
    );
};

export default FetchedBillsPanel;
