import { useCallback, useRef } from "react";

const DEFAULT_THROTTLE_DELAY_MS = 50;

/**
 * Return a memoized throttle function
 *
 * @returns
 */
export const useThrottleAsyncFunction = (
    func: (...args: any[]) => Promise<unknown>,
    delay = DEFAULT_THROTTLE_DELAY_MS,
    defaultResponseValue: any = undefined,
): ((...args: any[]) => Promise<unknown>) => {
    const throttleRef = useRef<boolean>(false);
    return useCallback(
        async (...args: any[]) => {
            if (throttleRef.current) {
                return defaultResponseValue;
            }
            throttleRef.current = true;
            func(...args).catch(console.error);
            setTimeout(() => {
                throttleRef.current = false;
            }, delay);
        },
        [func, delay, defaultResponseValue],
    );
};
