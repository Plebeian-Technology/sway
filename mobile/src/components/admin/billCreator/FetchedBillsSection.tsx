// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { parseTime, relativeTime } from "../../../utils/runTime";
import { FormField } from "../../ui/FormField";
import { Pressable } from "../../ui/Pressable";
import CollapsibleSection from "./CollapsibleSection";

export interface FetchedBillsRow {
    external_id: string;
    bill_id: number | null;
    title: string | null;
    fetched_at: string;
    pdf_present: boolean;
    metadata_present: boolean;
    bill_row_exists: boolean;
}

interface FetchedBillsSectionProps {
    rows: FetchedBillsRow[];
}

type FreshnessTone = "success" | "warning" | "danger";
type FreshnessFilter = "all" | FreshnessTone;

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

const FRESHNESS_LABELS: Record<FreshnessTone, string> = {
    success: "fresh",
    warning: "stale",
    danger: "very stale",
};

const FILTER_CHIPS: { key: FreshnessFilter; label: string }[] = [
    { key: "all", label: "All" },
    { key: "success", label: "Fresh" },
    { key: "warning", label: "Stale" },
    { key: "danger", label: "Very stale" },
];

const TONE_CLASSES: Record<FreshnessTone, string> = {
    success: "text-success-light dark:text-success-dark",
    warning: "text-warning-foreground-light dark:text-warning-foreground-dark",
    danger: "text-destructive-light dark:text-destructive-dark",
};

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";

const freshnessTone = (fetchedAt: string): FreshnessTone => {
    const ageMs = Date.now() - (parseTime(fetchedAt)?.getTime() ?? 0);
    if (ageMs < SEVEN_DAYS_MS) return "success";
    if (ageMs < THIRTY_DAYS_MS) return "warning";
    return "danger";
};

const FetchedBillRow: React.FC<{ row: FetchedBillsRow }> = ({ row }) => {
    const tone = freshnessTone(row.fetched_at);
    const fetched = parseTime(row.fetched_at);
    return (
        <View
            testID={`admin-fetched-bill-${row.external_id}`}
            className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1"
        >
            <Text className={labelText}>{row.external_id}</Text>
            {row.bill_row_exists && row.bill_id !== null ? (
                <Text className={labelText}>{row.title ?? row.external_id}</Text>
            ) : (
                <Text className={mutedText}>(orphan on disk)</Text>
            )}
            <Text className={mutedText}>
                <Text className={TONE_CLASSES[tone]}>{FRESHNESS_LABELS[tone]}</Text>
                {fetched ? ` ${relativeTime(fetched)}` : ""}
            </Text>
            <Text className={mutedText}>{row.pdf_present ? "PDF ✓" : "PDF —"}</Text>
        </View>
    );
};

const matchesQuery = (row: FetchedBillsRow, query: string) =>
    row.external_id.toLowerCase().includes(query) || (row.title?.toLowerCase().includes(query) ?? false);

const FetchedBillsSection: React.FC<FetchedBillsSectionProps> = ({ rows }) => {
    const [query, setQuery] = useState("");
    const [filter, setFilter] = useState<FreshnessFilter>("all");

    const trimmedQuery = query.trim().toLowerCase();
    const filteredRows = rows.filter(
        (row) =>
            (filter === "all" || freshnessTone(row.fetched_at) === filter) &&
            (trimmedQuery === "" || matchesQuery(row, trimmedQuery)),
    );
    const isFiltering = trimmedQuery !== "" || filter !== "all";
    const clearFilters = () => {
        setQuery("");
        setFilter("all");
    };

    return (
        <CollapsibleSection testID="admin-fetched-bills" title="Fetched bills (on disk)">
            {rows.length === 0 ? (
                <Text className={mutedText}>No bill artifacts on disk yet. Run the fetch-bills stage to populate.</Text>
            ) : (
                <>
                    <Text testID="admin-fetched-bills-count" className={mutedText}>
                        {isFiltering
                            ? `${filteredRows.length} of ${rows.length} bills`
                            : `${rows.length} ${rows.length === 1 ? "bill" : "bills"}`}
                    </Text>
                    <FormField
                        testID="admin-fetched-bills-search"
                        label="Search external ID or title"
                        value={query}
                        onChangeText={setQuery}
                    />
                    <View className="flex-row flex-wrap gap-2">
                        {FILTER_CHIPS.map((chip) => (
                            <Pressable
                                key={chip.key}
                                testID={`admin-fetched-bills-filter-${chip.key}`}
                                variant={filter === chip.key ? "default" : "outline"}
                                accessibilityState={{ selected: filter === chip.key }}
                                onPress={() => setFilter(chip.key)}
                            >
                                <Text className={labelText}>{chip.label}</Text>
                            </Pressable>
                        ))}
                    </View>
                    {filteredRows.length === 0 ? (
                        <View className="gap-2">
                            <Text className={mutedText}>No bills match.</Text>
                            <Pressable testID="admin-fetched-bills-clear" variant="outline" onPress={clearFilters}>
                                <Text className={labelText}>Clear filters</Text>
                            </Pressable>
                        </View>
                    ) : (
                        filteredRows.map((row) => <FetchedBillRow key={row.external_id} row={row} />)
                    )}
                </>
            )}
        </CollapsibleSection>
    );
};

export default FetchedBillsSection;
