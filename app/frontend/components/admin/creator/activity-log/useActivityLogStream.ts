import { router, usePage } from "@inertiajs/react";
import { useCallback, useEffect, useRef, useState } from "react";
import { subscribeActivityLog } from "app/frontend/channels/activityLogChannel";
import type {
    ActivityLogEntry,
    ActivityLogSeverityFilter,
    ActivityLogSubjectFilter,
    ActivityLogWindowFilter,
} from "app/frontend/types/activityLog";
import { buildFilterParams } from "app/frontend/components/admin/creator/activity-log/filterParams";
import { currentAddressWithout } from "app/frontend/sway_utils/currentAddressWithout";

const ONLY_PROPS = ["activity_log_entries", "activity_log_next_cursor", "activity_log_has_more"];

// @lat: [[activity-log-stream#Why the URL param list includes the cursor]]
const ACTIVITY_LOG_URL_PARAMS = ["subject", "severity", "window", "cursor"];

// @lat: [[pagination#A cursor-paged list managing its own state]]
const CLIENT_PAGE_SIZE = 10;

interface ActivityLogStreamProps {
    activity_log_entries?: ActivityLogEntry[];
    activity_log_next_cursor?: string | null;
    activity_log_has_more?: boolean;
}

export interface ActivityLogStream {
    pageEntries: ActivityLogEntry[];
    page: number;
    pageCount: number;
    hasMore: boolean;
    isLoadingMore: boolean;
    goToPage: (page: number) => void;
    handleLoadMore: () => void;
    onFilterChange: (nextParams: Record<string, string>) => void;
    pendingLiveCount: number;
    showPendingLiveEntries: () => void;
}

// @lat: [[activity-log-stream#What the hook owns]]
export const useActivityLogStream = (currentRunRemoteId?: string | null): ActivityLogStream => {
    const pageProps = usePage().props as ActivityLogStreamProps;

    const [buffer, setBuffer] = useState<ActivityLogEntry[]>(() => pageProps.activity_log_entries ?? []);
    const [nextCursor, setNextCursor] = useState<string | null>(pageProps.activity_log_next_cursor ?? null);
    const [hasMore, setHasMore] = useState<boolean>(pageProps.activity_log_has_more ?? false);
    const [requestedPage, setRequestedPage] = useState(1);
    const [isLoadingMore, setIsLoadingMore] = useState(false);
    const [pendingLive, setPendingLive] = useState<ActivityLogEntry[]>([]);

    const bufferIdsRef = useRef<Set<number>>(new Set(buffer.map((e) => e.id)));
    const bufferLengthRef = useRef<number>(buffer.length);
    useEffect(() => {
        bufferIdsRef.current = new Set(buffer.map((e) => e.id));
        bufferLengthRef.current = buffer.length;
    }, [buffer]);

    // @lat: [[activity-log-stream#Why the reset effect skips once for a load-more fetch]]
    const extendingRef = useRef<boolean>(false);

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    const filterVisitsInFlightRef = useRef<number>(0);
    const queuedLoadMoreRef = useRef<boolean>(false);
    const nextCursorRef = useRef<string | null>(nextCursor);
    useEffect(() => {
        nextCursorRef.current = nextCursor;
    }, [nextCursor]);

    const pageCount = Math.max(1, Math.ceil(buffer.length / CLIENT_PAGE_SIZE));
    // @lat: [[activity-log-stream#The page number is clamped where it is read]]
    const page = Math.min(requestedPage, pageCount);
    const pageEntries = buffer.slice((page - 1) * CLIENT_PAGE_SIZE, page * CLIENT_PAGE_SIZE);

    // @lat: [[activity-log-stream#Live entries never auto-insert into the buffer]]
    const onAppend = useCallback((entry: ActivityLogEntry) => {
        if (bufferIdsRef.current.has(entry.id)) return;
        setPendingLive((prev) => (prev.some((e) => e.id === entry.id) ? prev : [entry, ...prev]));
    }, []);

    // @lat: [[activity-log-stream#Listen on two channels]]
    useEffect(() => {
        const unsubscribeRun = currentRunRemoteId ? subscribeActivityLog(currentRunRemoteId, onAppend) : () => {};
        const unsubscribeGlobal = subscribeActivityLog("global", onAppend);
        return () => {
            unsubscribeRun();
            unsubscribeGlobal();
        };
    }, [currentRunRemoteId, onAppend]);

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    const fetchOlder = useCallback((cursor: string, filters?: Record<string, string>) => {
        setIsLoadingMore(true);
        extendingRef.current = true;
        const params = new URLSearchParams(window.location.search);
        const current = {
            subject: (params.get("subject") ?? "all_bills") as ActivityLogSubjectFilter,
            severity: (params.get("severity") ?? "all") as ActivityLogSeverityFilter,
            window: (params.get("window") ?? "7d") as ActivityLogWindowFilter,
        };
        router.get(
            currentAddressWithout(ACTIVITY_LOG_URL_PARAMS),
            { ...(filters ?? buildFilterParams(current, {})), cursor },
            {
                only: ONLY_PROPS,
                preserveScroll: true,
                preserveState: true,
                onSuccess: (visitPage) => {
                    const props = visitPage.props as unknown as ActivityLogStreamProps;
                    const older = props.activity_log_entries ?? [];
                    setBuffer((prev) => {
                        const seen = new Set(prev.map((e) => e.id));
                        return [...prev, ...older.filter((e) => !seen.has(e.id))];
                    });
                    setNextCursor(props.activity_log_next_cursor ?? null);
                    setHasMore(props.activity_log_has_more ?? false);
                    setRequestedPage(Math.floor(bufferLengthRef.current / CLIENT_PAGE_SIZE) + 1);
                },
                onFinish: () => {
                    extendingRef.current = false;
                    setIsLoadingMore(false);
                },
            },
        );
    }, []);

    // @lat: [[activity-log-stream#Why the reset effect skips once for a load-more fetch]]
    useEffect(() => {
        if (extendingRef.current) {
            extendingRef.current = false;
            return;
        }
        setBuffer(pageProps.activity_log_entries ?? []);
        setNextCursor(pageProps.activity_log_next_cursor ?? null);
        setHasMore(pageProps.activity_log_has_more ?? false);
        setRequestedPage(1);
        setPendingLive([]);
    }, [pageProps.activity_log_entries, pageProps.activity_log_next_cursor, pageProps.activity_log_has_more]);

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    const onFilterChange = useCallback(
        (nextParams: Record<string, string>) => {
            filterVisitsInFlightRef.current += 1;
            router.get(currentAddressWithout(ACTIVITY_LOG_URL_PARAMS), nextParams, {
                only: ONLY_PROPS,
                preserveScroll: true,
                preserveState: true,
                onSuccess: (visitPage) => {
                    if (!queuedLoadMoreRef.current) return;
                    queuedLoadMoreRef.current = false;
                    const props = visitPage.props as unknown as ActivityLogStreamProps;
                    const cursor = props.activity_log_next_cursor ?? null;
                    if (cursor) fetchOlder(cursor, nextParams);
                },
                // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
                onError: () => {
                    if (!queuedLoadMoreRef.current) return;
                    queuedLoadMoreRef.current = false;
                    const cursor = nextCursorRef.current;
                    if (cursor) fetchOlder(cursor);
                },
                onFinish: () => {
                    filterVisitsInFlightRef.current -= 1;
                },
            });
        },
        [fetchOlder],
    );

    const goToPage = useCallback(
        (target: number) => {
            setRequestedPage(Math.min(Math.max(1, target), pageCount));
        },
        [pageCount],
    );

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    const handleLoadMore = useCallback(() => {
        if (isLoadingMore) return;
        if (filterVisitsInFlightRef.current > 0) {
            queuedLoadMoreRef.current = true;
            return;
        }
        if (!nextCursor) return;
        fetchOlder(nextCursor);
    }, [nextCursor, isLoadingMore, fetchOlder]);

    // @lat: [[activity-log-stream#Live entries never auto-insert into the buffer]]
    const showPendingLiveEntries = useCallback(() => {
        setBuffer((prev) => {
            const seen = new Set(prev.map((e) => e.id));
            const newOnes = pendingLive.filter((e) => !seen.has(e.id));
            return newOnes.length > 0 ? [...newOnes, ...prev] : prev;
        });
        setPendingLive([]);
        setRequestedPage(1);
    }, [pendingLive]);

    return {
        pageEntries,
        page,
        pageCount,
        hasMore,
        isLoadingMore,
        goToPage,
        handleLoadMore,
        onFilterChange,
        pendingLiveCount: pendingLive.length,
        showPendingLiveEntries,
    };
};
