import { router } from "@inertiajs/react";
import { isPlainObject } from "lodash";
import { useCallback, useEffect, useRef } from "react";

// @lat: [[use-search-params-design#INavOptions fields]]
export interface INavOptions {
    only?: string[];
    debounceMs?: number;
}

export const useSearchParams = () => {
    // @lat: [[use-search-params-design#Why the query string is re-read on every render]]
    const params = new URLSearchParams(window.location.search);

    const entries: Record<string, string> = {};
    for (const [key, value] of params.entries()) {
        entries[key] = value;
    }

    const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    // @lat: [[use-search-params-design#Why the debounce timer is cleared on unmount]]
    useEffect(
        () => () => {
            if (debounceTimerRef.current) {
                clearTimeout(debounceTimerRef.current);
            }
        },
        [],
    );

    const dispatchNavigation = useCallback((target: string, onlyProps: string[] | undefined, isRemove: boolean) => {
        router.get(
            target,
            {},
            {
                preserveScroll: true,
                ...(isRemove ? { preserveState: true, replace: true } : {}),
                ...(onlyProps ? { only: onlyProps } : {}),
            },
        );
    }, []);

    const scheduleNavigation = useCallback(
        (target: string, options: INavOptions | undefined, isRemove: boolean) => {
            const onlyProps = options?.only;
            const debounceMs = options?.debounceMs ?? 0;
            if (debounceTimerRef.current) {
                clearTimeout(debounceTimerRef.current);
                debounceTimerRef.current = null;
            }
            if (debounceMs > 0) {
                debounceTimerRef.current = setTimeout(() => {
                    debounceTimerRef.current = null;
                    dispatchNavigation(target, onlyProps, isRemove);
                }, debounceMs);
                return;
            }
            dispatchNavigation(target, onlyProps, isRemove);
        },
        [dispatchNavigation],
    );

    const get = useCallback((key: string) => {
        return new URLSearchParams(window.location.search).get(key);
    }, []);

    const add = useCallback(
        (key: string | string[] | Record<string, string>, value?: string | string[], options?: INavOptions) => {
            const freshParams = new URLSearchParams(window.location.search);
            if (isPlainObject(key)) {
                const newParams = key as Record<string, string>;
                Object.keys(newParams).forEach((k) => freshParams.set(k, newParams[k]));
            } else {
                if (!value) return;
                const keys = (Array.isArray(key) ? key : [key]) as string[];
                const values = Array.isArray(value) ? value : [value];
                keys.forEach((k, i) => freshParams.set(k, values[i]));
            }
            scheduleNavigation(
                `${window.location.origin}${window.location.pathname}?${freshParams.toString()}`,
                options,
                false,
            );
        },
        [scheduleNavigation],
    );

    const remove = useCallback(
        (key: string | string[] | Record<string, string>, value?: string | string[], options?: INavOptions) => {
            const freshParams = new URLSearchParams(window.location.search);
            if (typeof key === "string") {
                freshParams.delete(key);
            } else if (isPlainObject(key)) {
                const newParams = key as Record<string, string>;
                Object.keys(newParams).forEach((k) => {
                    freshParams.delete(k, newParams[k]);
                });
            } else {
                const keys = (Array.isArray(key) ? key : [key]) as string[];
                const values = Array.isArray(value) ? value : [value];
                keys.forEach((k, i) => {
                    freshParams.delete(k, values[i]);
                });
            }

            scheduleNavigation(
                `${window.location.origin}${window.location.pathname}?${freshParams.toString()}`,
                options,
                true,
            );
        },
        [scheduleNavigation],
    );

    return {
        entries,
        qs: params.toString(),
        get,
        add,
        remove,
    };
};
