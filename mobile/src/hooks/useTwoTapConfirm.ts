import { useCallback, useEffect, useRef, useState } from "react";

const CONFIRM_WINDOW_MS = 3000;

export function useTwoTapConfirm() {
    const [confirming, setConfirming] = useState(false);
    const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    const disarm = useCallback(() => {
        if (timeoutRef.current) clearTimeout(timeoutRef.current);
        setConfirming(false);
    }, []);

    const arm = useCallback(() => {
        if (timeoutRef.current) clearTimeout(timeoutRef.current);
        setConfirming(true);
        timeoutRef.current = setTimeout(() => setConfirming(false), CONFIRM_WINDOW_MS);
    }, []);

    useEffect(
        () => () => {
            if (timeoutRef.current) clearTimeout(timeoutRef.current);
        },
        [],
    );

    return { confirming, arm, disarm };
}
