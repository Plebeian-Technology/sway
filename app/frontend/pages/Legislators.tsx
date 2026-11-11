// @lat: [[legislator-directory-layouts#Legislators page container]]

import { router, usePoll } from "@inertiajs/react";
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { useSwayLocale, useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";
import { formatTermWindow } from "app/frontend/sway_utils/termWindow";
import {
    DefaultLegislatorsLayout,
    legislatorsLayoutFor,
    type ILegislatorsLayoutProps,
} from "app/frontend/components/legislators/layouts";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    sway_locale: sway.ISwayLocale;
    legislators: sway.ILegislator[];
    waiting_for_new_term: boolean;
    filters: {
        search?: string;
    };
    history?: sway.legislatorHistory.IHistory;
}

// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
type TTab = "current" | "lifetime" | "history";

const isTab = (value: string | null): value is TTab =>
    value === "current" || value === "lifetime" || value === "history";

// @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
const readTabFromUrl = (): TTab | undefined => {
    if (typeof window === "undefined") return undefined;
    const params = new URLSearchParams(window.location.search);
    const legislatorsTab = params.get("legislators_tab");
    if (params.has("legislators_tab")) {
        return isTab(legislatorsTab) ? legislatorsTab : undefined;
    }

    const legacyTab = params.get("tab");
    return isTab(legacyTab) ? legacyTab : undefined;
};

const POLLING_PROPS = ["legislators"];

const LOCALE_SWITCH_PROPS = ["legislators", "sway_locale"];
const LOCALE_SWITCH_PROPS_WITH_HISTORY = ["legislators", "sway_locale", "history"];

const computeRosterSignature = (reps: sway.ILegislator[]) =>
    reps
        .map((l) => [l.id, l.active ?? "", l.ended_on ?? "", l.term_start_year ?? "", l.term_end_year ?? ""].join(":"))
        .sort()
        .join(",");

const hasTrackedRosterChanged = (
    prev: { localeId: number | undefined; signature: string },
    localeId: number | undefined,
    signature: string,
    historyRequestedFor: number | undefined,
) =>
    localeId !== undefined &&
    prev.localeId === localeId &&
    prev.signature !== signature &&
    historyRequestedFor === localeId;

const Legislators: React.FC<IProps> = ({ legislators, waiting_for_new_term, history }) => {
    usePoll(15000, { only: POLLING_PROPS }, { background: "pause" });
    useScoreSubscription(POLLING_PROPS);
    const [tab, setTab] = useState<TTab>(() => readTabFromUrl() ?? "current");
    const tabRef = useRef(tab);
    const [swayLocale, getSwayLocale, pendingSwayLocaleId] = useSwayLocale(
        tab === "history" ? LOCALE_SWITCH_PROPS_WITH_HISTORY : LOCALE_SWITCH_PROPS,
    );
    const { options } = useSwayLocales();

    // @lat: [[legislators-history-per-locale-state#Legislators History state is tracked per locale]]
    const swayLocaleId = swayLocale?.id;

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    const [historyRequestedFor, setHistoryRequestedFor] = useState<number | undefined>(() =>
        history !== undefined ? swayLocaleId : undefined,
    );
    // @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]
    const [historyFor, setHistoryFor] = useState<number | undefined>(() =>
        history !== undefined ? swayLocaleId : undefined,
    );
    // @lat: [[legislators-history-per-locale-state#Why requestHistory is one path for both the first open and a retry]]
    const [historyFailedFor, setHistoryFailedFor] = useState<number | undefined>(undefined);

    const historyRequested = historyRequestedFor === swayLocaleId;
    const historyFailed = historyFailedFor === swayLocaleId;
    const currentHistory = historyFor === swayLocaleId ? history : undefined;

    const reps = useMemo(
        () => (legislators ?? []).filter((legislator) => !swayLocaleId || legislator.sway_locale_id === swayLocaleId),
        [legislators, swayLocaleId],
    );

    const handleFindLegislators = useCallback(() => {
        if (!swayLocaleId) return;

        router.post(
            "/user_legislators",
            { sway_locale_id: swayLocaleId },
            {
                preserveState: true,
                preserveScroll: true,
                onSuccess: () => router.reload({ only: ["legislators", "waiting_for_new_term"] }),
            },
        );
    }, [swayLocaleId]);

    const rosterSignature = useMemo(() => computeRosterSignature(reps), [reps]);
    const prevRosterRef = useRef<{ localeId: number | undefined; signature: string }>({
        localeId: swayLocaleId,
        signature: rosterSignature,
    });
    const switchTargetIdRef = useRef<number | undefined>(undefined);
    const stampsBeforeSwitchRef = useRef<{
        historyFor: number | undefined;
        historyRequestedFor: number | undefined;
        historyFailedFor: number | undefined;
    }>({ historyFor, historyRequestedFor, historyFailedFor });

    // @lat: [[legislators-history-per-locale-state#Why requestHistory is one path for both the first open and a retry]]
    const requestHistory = useCallback(() => {
        prevRosterRef.current = { localeId: swayLocaleId, signature: rosterSignature };
        setHistoryRequestedFor(swayLocaleId);
        setHistoryFor(undefined);
        setHistoryFailedFor(undefined);
        router.reload({
            only: ["history"],
            onSuccess: () => setHistoryFor(swayLocaleId),
            onError: () => setHistoryFailedFor(swayLocaleId),
        });
    }, [swayLocaleId, rosterSignature]);

    // @lat: [[legislators-history-per-locale-state#Invalidating History when active roster changes on poll]]
    useEffect(() => {
        tabRef.current = tab;
        if (switchTargetIdRef.current !== undefined) {
            if (swayLocaleId === switchTargetIdRef.current) {
                switchTargetIdRef.current = undefined;
                prevRosterRef.current = { localeId: swayLocaleId, signature: rosterSignature };
                if (historyRequestedFor === swayLocaleId && currentHistory === undefined && !historyFailed) {
                    if (tab === "history") {
                        // oxlint-disable-next-line react/set-state-in-effect
                        requestHistory();
                    } else {
                        setHistoryRequestedFor(undefined);
                    }
                }
            }
            return;
        }
        const prev = prevRosterRef.current;
        if (hasTrackedRosterChanged(prev, swayLocaleId, rosterSignature, historyRequestedFor)) {
            if (tab === "history") {
                // oxlint-disable-next-line react/set-state-in-effect
                requestHistory();
            } else {
                setHistoryRequestedFor(undefined);
                setHistoryFor(undefined);
                setHistoryFailedFor(undefined);
            }
        }
        prevRosterRef.current = { localeId: swayLocaleId, signature: rosterSignature };
    }, [swayLocaleId, rosterSignature, historyRequestedFor, tab, currentHistory, historyFailed, requestHistory]);

    const handleTabChange = useCallback(
        (value: string) => {
            if (!isTab(value)) return;
            tabRef.current = value;
            setTab(value);

            // @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
            // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
            const url = new URL(window.location.href);
            if (value === "current") {
                setQueryParamCleared(url.searchParams, "legislators_tab");
                if (url.searchParams.has("tab")) {
                    setQueryParamCleared(url.searchParams, "tab");
                }
            } else {
                url.searchParams.set("legislators_tab", value);
                if (url.searchParams.has("tab")) {
                    setQueryParamCleared(url.searchParams, "tab");
                } else {
                    url.searchParams.delete("tab");
                }
            }
            window.history.replaceState(window.history.state, "", url);

            if (value === "history") {
                const targetId = switchTargetIdRef.current;
                if (targetId !== undefined && targetId !== swayLocaleId) {
                    if (historyRequestedFor !== targetId) {
                        setHistoryRequestedFor(targetId);
                        setHistoryFailedFor(undefined);
                    }
                } else if (!historyRequested) {
                    requestHistory();
                }
            }
        },
        [swayLocaleId, historyRequestedFor, historyRequested, requestHistory],
    );

    // @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]
    const handleLocaleChange = useCallback(
        (id: number) => {
            if (switchTargetIdRef.current === undefined && id === swayLocaleId) return;
            if (switchTargetIdRef.current === undefined) {
                stampsBeforeSwitchRef.current = { historyFor, historyRequestedFor, historyFailedFor };
            }
            const carriesHistory = tab === "history";
            switchTargetIdRef.current = id === swayLocaleId ? undefined : id;
            if (id === swayLocaleId) {
                setHistoryFor(carriesHistory ? id : stampsBeforeSwitchRef.current.historyFor);
                setHistoryRequestedFor(carriesHistory ? id : stampsBeforeSwitchRef.current.historyRequestedFor);
                setHistoryFailedFor(carriesHistory ? undefined : stampsBeforeSwitchRef.current.historyFailedFor);
            } else {
                setHistoryFor(carriesHistory ? id : undefined);
                setHistoryRequestedFor(carriesHistory ? id : undefined);
                setHistoryFailedFor(undefined);
            }
            getSwayLocale(id, {
                onError: () => {
                    switchTargetIdRef.current = undefined;
                    if (
                        tabRef.current === "history" &&
                        stampsBeforeSwitchRef.current.historyRequestedFor !== swayLocaleId
                    ) {
                        requestHistory();
                    } else {
                        setHistoryFor(stampsBeforeSwitchRef.current.historyFor);
                        setHistoryRequestedFor(stampsBeforeSwitchRef.current.historyRequestedFor);
                        setHistoryFailedFor(stampsBeforeSwitchRef.current.historyFailedFor);
                    }
                },
            });
        },
        [tab, getSwayLocale, historyFor, historyRequestedFor, historyFailedFor, swayLocaleId, requestHistory],
    );

    const isHistoryLoading = tab === "history" && historyRequested && currentHistory === undefined && !historyFailed;

    // @lat: [[legislators-tab-switching-design#The Current | Lifetime toggle and why an open accordion used to close on flip]]
    const firstRep = reps[0];
    const termYearRange = formatTermWindow({
        term_start_year: firstRep?.term_start_year,
        term_end_year: firstRep?.term_end_year,
    });

    const themeId = useActiveThemeId();
    const layout = legislatorsLayoutFor(themeId);

    const layoutProps: ILegislatorsLayoutProps = {
        legislators: legislators ?? [],
        activeLegislators: reps,
        activeTab: tab,
        onTabChange: handleTabChange,
        currentLocale: swayLocale,
        localeOptions: options,
        selectedLocaleId: pendingSwayLocaleId ?? swayLocaleId,
        onLocaleChange: handleLocaleChange,
        waitingForNewTerm: waiting_for_new_term,
        onFindLegislators: handleFindLegislators,
        currentHistory,
        isHistoryLoading,
        historyFailed,
        onRetryHistory: requestHistory,
        termRange: termYearRange,
    };

    return (
        <React.Suspense fallback={<DefaultLegislatorsLayout {...layoutProps} />}>
            {/* oxlint-disable-next-line react/refs */}
            {React.createElement(layout, layoutProps)}
        </React.Suspense>
    );
};

export default Legislators;
