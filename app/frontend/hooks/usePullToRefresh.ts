import { useEffect, useRef, useState } from "react";

export interface UsePullToRefreshOptions {
    onRefresh: () => void | Promise<void>;
    threshold?: number;
    scopeRef?: React.RefObject<HTMLElement | null>;
}

export const usePullToRefresh = ({ onRefresh, threshold = 80, scopeRef }: UsePullToRefreshOptions) => {
    const [pulling, setPulling] = useState(false);
    const [pullDistance, setPullDistance] = useState(0);
    const startYRef = useRef<number | null>(null);
    const pullDistanceRef = useRef<number>(0);

    // @lat: [[navigation-placeholder-tracer#Why usePullToRefresh holds onRefresh in a ref]]
    const onRefreshRef = useRef(onRefresh);
    useEffect(() => {
        onRefreshRef.current = onRefresh;
    });

    useEffect(() => {
        if (typeof window === "undefined") return;
        if (!window.matchMedia("(display-mode: standalone)").matches) return;
        const target: HTMLElement | Document = scopeRef?.current ?? document;

        const handleStart = (e: Event) => {
            const touch = (e as TouchEvent).touches[0];
            const scrollTop = document.scrollingElement?.scrollTop ?? 0;
            if (scrollTop <= 0 && touch) {
                startYRef.current = touch.clientY;
                setPulling(true);
            }
        };

        const handleMove = (e: Event) => {
            if (startYRef.current === null) return;
            const touch = (e as TouchEvent).touches[0];
            if (!touch) return;
            const delta = Math.max(0, touch.clientY - startYRef.current);
            pullDistanceRef.current = delta;
            setPullDistance(delta);
        };

        const handleEnd = async () => {
            const distance = pullDistanceRef.current;
            startYRef.current = null;
            pullDistanceRef.current = 0;
            setPulling(false);
            setPullDistance(0);
            if (distance > threshold) {
                await onRefreshRef.current();
            }
        };

        target.addEventListener("touchstart", handleStart, { passive: true });
        target.addEventListener("touchmove", handleMove, { passive: true });
        target.addEventListener("touchend", handleEnd);
        return () => {
            target.removeEventListener("touchstart", handleStart);
            target.removeEventListener("touchmove", handleMove);
            target.removeEventListener("touchend", handleEnd);
        };
    }, [threshold, scopeRef]);

    return { pulling, pullDistance };
};
