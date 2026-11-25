// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { apiClient } from "../../../api/client";
import { Routes } from "../../../api/routes";
import { parseTime, relativeTime } from "../../../utils/runTime";
import type { BillCreatorProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";
import CollapsibleSection from "./CollapsibleSection";

export interface ActivityLogEntry {
    id: number;
    event_type: string;
    severity: "info" | "warning" | "error";
    title: string;
    message: string;
    subject_type: string | null;
    subject_id: string | null;
    subject_label: string | null;
    actor_user_id: number | null;
    payload: Record<string, unknown>;
    inspect_query: string;
    created_at: string;
}

interface ActivityLogSectionProps {
    billId: number | null;
    entries: ActivityLogEntry[];
    nextCursor: string | null;
    hasMore: boolean;
}

interface OlderPage {
    entries: ActivityLogEntry[];
    nextCursor: string | null;
    hasMore: boolean;
}

const SEVERITY_TONES: Record<ActivityLogEntry["severity"], string> = {
    error: "text-destructive-light dark:text-destructive-dark",
    warning: "text-warning-foreground-light dark:text-warning-foreground-dark",
    info: "text-accent-light dark:text-accent-dark",
};

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const errorText = "text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";

const ageText = (iso: string) => {
    const date = parseTime(iso);
    return date ? relativeTime(date) : "—";
};

const EntryRow: React.FC<{ entry: ActivityLogEntry }> = ({ entry }) => {
    const [detailsOpen, setDetailsOpen] = useState(false);
    return (
        <View
            testID={`admin-activity-log-entry-${entry.id}`}
            className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1"
        >
            <Text className={`text-xs font-open-sans-semibold ${SEVERITY_TONES[entry.severity]}`}>
                {entry.severity}
            </Text>
            <Text className={labelText}>{entry.title}</Text>
            {entry.subject_label ? <Text className={mutedText}>{entry.subject_label}</Text> : null}
            <Text className={mutedText}>
                {entry.actor_user_id ? `User #${entry.actor_user_id}` : "System"} · {ageText(entry.created_at)}
            </Text>
            {entry.message ? <Text className={bodyText}>{entry.message}</Text> : null}
            <Pressable
                testID={`admin-activity-log-details-toggle-${entry.id}`}
                variant="ghost"
                accessibilityState={{ expanded: detailsOpen }}
                onPress={() => setDetailsOpen(!detailsOpen)}
                className="items-start px-0"
            >
                <Text className={mutedText}>Details</Text>
            </Pressable>
            {detailsOpen ? (
                <View testID={`admin-activity-log-details-${entry.id}`} className="gap-2">
                    <Text selectable className={mutedText}>
                        {JSON.stringify(entry.payload, null, 2)}
                    </Text>
                    {entry.inspect_query ? (
                        <Text selectable className={mutedText}>
                            {entry.inspect_query}
                        </Text>
                    ) : null}
                </View>
            ) : null}
        </View>
    );
};

const ActivityLogSection: React.FC<ActivityLogSectionProps> = ({ billId, entries, nextCursor, hasMore }) => {
    const [older, setOlder] = useState<OlderPage | null>(null);
    const [loadingOlder, setLoadingOlder] = useState(false);
    const [loadError, setLoadError] = useState<string | null>(null);

    const cursor = older ? older.nextCursor : nextCursor;
    const moreAvailable = older ? older.hasMore : hasMore;
    const shownIds = new Set(entries.map((entry) => entry.id));
    const shownEntries = [...entries, ...(older?.entries ?? []).filter((entry) => !shownIds.has(entry.id))];

    const loadOlder = async () => {
        if (!cursor || loadingOlder) return;
        setLoadingOlder(true);
        setLoadError(null);
        try {
            const page = await apiClient.get<BillCreatorProps>(Routes.adminBillCreatorActivityLog(billId, cursor));
            setOlder({
                entries: [...(older?.entries ?? []), ...((page.activity_log_entries as ActivityLogEntry[]) ?? [])],
                nextCursor: (page.activity_log_next_cursor as string | null) ?? null,
                hasMore: (page.activity_log_has_more as boolean) ?? false,
            });
        } catch (e: unknown) {
            setLoadError(e instanceof Error ? e.message : String(e));
        } finally {
            setLoadingOlder(false);
        }
    };

    return (
        <CollapsibleSection testID="admin-activity-log" title="Activity log">
            {shownEntries.length === 0 ? (
                <View className="gap-1">
                    <Text className={labelText}>No activity yet</Text>
                    <Text className={mutedText}>Pipeline events will appear here as they happen.</Text>
                </View>
            ) : (
                shownEntries.map((entry) => <EntryRow key={entry.id} entry={entry} />)
            )}
            {moreAvailable && cursor ? (
                <Pressable
                    testID="admin-activity-log-load-more"
                    variant="outline"
                    disabled={loadingOlder}
                    onPress={() => void loadOlder()}
                >
                    <Text className={labelText}>{loadingOlder ? "Loading…" : "Load older entries"}</Text>
                </Pressable>
            ) : null}
            {loadError ? (
                <Text testID="admin-activity-log-load-more-error" className={errorText}>
                    {loadError}
                </Text>
            ) : null}
        </CollapsibleSection>
    );
};

export default ActivityLogSection;
