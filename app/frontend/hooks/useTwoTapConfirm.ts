import { useCallback, useEffect, useRef, useState } from "react";

export interface ITwoTapConfirm {
    confirming: boolean;
    arm: () => void;
    disarm: () => void;
}

// @lat: [[two-tap-confirm-design#Why useTwoTapConfirm is a shared hook]]
export const useTwoTapConfirm = (timeoutMs: number = 3000): ITwoTapConfirm => {
    const [confirming, setConfirming] = useState(false);
    const confirmTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    const arm = useCallback(() => {
        if (confirmTimeoutRef.current) clearTimeout(confirmTimeoutRef.current);
        setConfirming(true);
        confirmTimeoutRef.current = setTimeout(() => setConfirming(false), timeoutMs);
    }, [timeoutMs]);

    const disarm = useCallback(() => {
        if (confirmTimeoutRef.current) clearTimeout(confirmTimeoutRef.current);
        setConfirming(false);
    }, []);

    useEffect(
        () => () => {
            if (confirmTimeoutRef.current) clearTimeout(confirmTimeoutRef.current);
        },
        [],
    );

    return { confirming, arm, disarm };
};
