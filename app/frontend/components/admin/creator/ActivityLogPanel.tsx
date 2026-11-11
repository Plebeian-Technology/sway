import { usePage } from "@inertiajs/react";
import { useEffect } from "react";
import type {
    ActivityLogEntry,
    ActivityLogSeverityFilter,
    ActivityLogSubjectFilter,
    ActivityLogWindowFilter,
} from "app/frontend/types/activityLog";
import { notify } from "app/frontend/sway_utils";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import Pagination from "app/frontend/components/Pagination";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import ActivityLogEntryRow from "app/frontend/components/admin/creator/activity-log/ActivityLogEntryRow";
import ActivityLogErrorBanner from "app/frontend/components/admin/creator/activity-log/ActivityLogErrorBanner";
import ActivityLogFilters from "app/frontend/components/admin/creator/activity-log/ActivityLogFilters";
import { useActivityLogStream } from "app/frontend/components/admin/creator/activity-log/useActivityLogStream";
import { useHighlightPulse } from "app/frontend/components/admin/creator/activity-log/useHighlightPulse";

interface IProps {
    currentBillId?: number;
    currentRunRemoteId?: string | null;
}

interface ActivityLogFlash {
    activity_log_entry?: ActivityLogEntry;
    // @lat: [[pipeline-activity-log-error-banner-fallback#Why each delivery path has its own rescue]]
    activity_log_error?: { entry_id: number; error_class: string };
}

const ActivityLogPanel: React.FC<IProps> = ({ currentBillId, currentRunRemoteId }) => {
    const flash = (usePage().props as { flash?: ActivityLogFlash }).flash;
    const activityLogError = flash?.activity_log_error ?? null;

    const {
        pageEntries,
        page,
        pageCount,
        hasMore,
        isLoadingMore,
        goToPage,
        handleLoadMore,
        onFilterChange,
        pendingLiveCount,
        showPendingLiveEntries,
    } = useActivityLogStream(currentRunRemoteId);
    useHighlightPulse();

    useEffect(() => {
        const flashEntry = flash?.activity_log_entry;
        if (flashEntry) {
            notify({
                id: `activity-log-${flashEntry.id}`,
                level: flashEntry.severity,
                title: flashEntry.title,
                message: flashEntry.message,
                duration: flashEntry.severity === "error" ? 8000 : 5000,
            });
        }
        // oxlint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const urlParams = new URLSearchParams(typeof window !== "undefined" ? window.location.search : "");
    const currentSubject = (urlParams.get("subject") ?? "all_bills") as ActivityLogSubjectFilter;
    const currentSeverity = (urlParams.get("severity") ?? "all") as ActivityLogSeverityFilter;
    const currentWindow = (urlParams.get("window") ?? "7d") as ActivityLogWindowFilter;

    return (
        <div className="col-span-full mt-6 flex max-w-full flex-col gap-4 overflow-hidden rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
            {activityLogError && <ActivityLogErrorBanner activityLogError={activityLogError} />}

            <div className="flex max-w-full flex-wrap items-center gap-2 overflow-x-auto py-1">
                <FeatureInfo note="pipeline.activityLog" />
                <ActivityLogFilters
                    currentBillId={currentBillId}
                    currentSubject={currentSubject}
                    currentSeverity={currentSeverity}
                    currentWindow={currentWindow}
                    onFilterChange={onFilterChange}
                />
            </div>

            {pendingLiveCount > 0 && (
                <div className="flex items-center gap-1.5 self-start">
                    <Button variant="outline" size="sm" onClick={showPendingLiveEntries}>
                        Show {pendingLiveCount} new {pendingLiveCount === 1 ? "entry" : "entries"}
                    </Button>
                    <FeatureInfo note="pipeline.activityLogNewEntries" />
                </div>
            )}

            {pageEntries.length === 0 ? (
                <Alert variant="default">
                    <AlertTitle>No activity yet</AlertTitle>
                    <AlertDescription>Pipeline events will appear here as they happen.</AlertDescription>
                </Alert>
            ) : (
                <div className="max-w-full overflow-x-auto">
                    <ul aria-label="Activity log entries" className="flex flex-col">
                        {pageEntries.map((entry) => (
                            <ActivityLogEntryRow key={entry.id} entry={entry} />
                        ))}
                    </ul>
                </div>
            )}

            <Pagination page={page} pageCount={pageCount} onPageChange={goToPage} className="justify-center pt-1" />

            {hasMore && page === pageCount && (
                <div className="flex items-center justify-center gap-1.5 pb-1">
                    <Button variant="outline" size="sm" disabled={isLoadingMore} onClick={handleLoadMore}>
                        {isLoadingMore ? "Loading…" : "Load older entries"}
                    </Button>
                    <FeatureInfo note="pipeline.activityLogOlder" />
                </div>
            )}
        </div>
    );
};

export default ActivityLogPanel;
