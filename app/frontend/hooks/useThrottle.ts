import { useCallback, useRef } from "react";

const DEFAULT_THROTTLE_DELAY_MS = 50;

type TThrottler = (func: (...args: any[]) => any, delay?: number) => any;

/**
 * Return a memoized throttle function
 *
 * @returns
 */
export const useThrottle = (): TThrottler => {
    const throttleRef = useRef<boolean>(false);
    return useCallback((func, delay = DEFAULT_THROTTLE_DELAY_MS) => {
        if (throttleRef.current) {
            return;
        }
        throttleRef.current = true;
        func();
        setTimeout(() => {
            throttleRef.current = false;
        }, delay);
    }, []);
};

/**
 * Return a memoized throttle function
 *
 * @returns
 */
type TFunc = (...args: any[]) => unknown;
export const useThrottleFunction = (
    func: TFunc | undefined,
    delay = DEFAULT_THROTTLE_DELAY_MS,
    defaultResponseValue: any = undefined,
): ((...args: any[]) => unknown) => {
    const throttleRef = useRef<boolean>(false);
    return useCallback(
        (...args: any[]) => {
            if (!func) return;

            if (throttleRef.current) {
                return defaultResponseValue;
            }
            throttleRef.current = true;
            func(...args);
            setTimeout(() => {
                throttleRef.current = false;
            }, delay);
        },
        [func, delay, defaultResponseValue],
    );
};
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
