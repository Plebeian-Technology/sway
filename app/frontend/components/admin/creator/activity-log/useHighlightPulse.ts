import { router } from "@inertiajs/react";
import { useEffect, useRef } from "react";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

// @lat: [[activity-log-stream#Why the highlight param is removed after use]]
export const useHighlightPulse = (): void => {
    const highlightIdRef = useRef<number | null>(null);
    const pulseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    useEffect(() => {
        const mountParams = new URLSearchParams(window.location.search);
        const highlightParam = mountParams.get("highlight");

        const applyClear = () => {
            const currentParams = new URLSearchParams(window.location.search);
            const currentVal = currentParams.get("highlight");
            if (currentVal === null || currentVal === "") {
                return;
            }

            const nextUrl = new URL(window.location.href);
            setQueryParamCleared(nextUrl.searchParams, "highlight");
            window.history.replaceState(window.history.state, "", nextUrl.toString());
            const routerPage = (router as unknown as { page?: { url: string } }).page;
            if (routerPage) {
                routerPage.url = nextUrl.pathname + nextUrl.search;
            }
        };

        const checkAndClear = () => {
            const params = new URLSearchParams(window.location.search);
            const currentHighlight = params.get("highlight");
            const routerPageUrl = (router as unknown as { page?: { url: string } }).page?.url;
            const routerHighlight = routerPageUrl
                ? new URL(routerPageUrl, "https://sway.test").searchParams.get("highlight")
                : null;
            if (
                (currentHighlight !== null && currentHighlight !== "") ||
                (routerHighlight !== null && routerHighlight !== "")
            ) {
                applyClear();
            }
        };

        if (highlightParam) {
            const highlightId = parseInt(highlightParam, 10);
            if (!isNaN(highlightId)) {
                highlightIdRef.current = highlightId;
                applyClear();

                const rowEl = document.getElementById(`activity-log-entry-${highlightId}`);
                if (rowEl) {
                    rowEl.scrollIntoView({ behavior: "smooth", block: "nearest" });
                    rowEl.classList.add("animate-[activity-log-pulse_3s_ease-out_1_forwards]");
                    rowEl.setAttribute("aria-live", "polite");
                    pulseTimerRef.current = setTimeout(() => {
                        rowEl.classList.remove("animate-[activity-log-pulse_3s_ease-out_1_forwards]");
                        rowEl.removeAttribute("aria-live");
                        highlightIdRef.current = null;
                    }, 3000);
                }
            }
        }

        const timer = setTimeout(checkAndClear, 100);

        const unregisterNavigate = typeof router?.on === "function" ? router.on("navigate", checkAndClear) : undefined;

        const unregisterFinish = typeof router?.on === "function" ? router.on("finish", checkAndClear) : undefined;

        return () => {
            clearTimeout(timer);
            if (pulseTimerRef.current) {
                clearTimeout(pulseTimerRef.current);
            }
            if (typeof unregisterNavigate === "function") unregisterNavigate();
            if (typeof unregisterFinish === "function") unregisterFinish();
        };
    }, []);
};
