import { router } from "@inertiajs/react";
import { isPlainObject } from "lodash";
import { useCallback, useMemo } from "react";

type TKey = string | string[] | Record<string, string>;
type TValue = string | string[];

export interface IParams {
    entries: Record<string, string>;
    qs: string;
    get: (key: string) => string | null;
    add: (key: TKey, value: TValue) => void;
    remove: (key: TKey, value?: TValue) => void;
}

export const useSearchParams = () => {
    const params = useMemo(() => new URLSearchParams(window.location.search), []);

    const entries = useMemo(() => {
        const object: Record<string, string> = {};
        for (const [key, value] of params.entries()) {
            object[key] = value;
        }
        return object;
    }, [params]);

    const get = useCallback(
        (key: string) => {
            return params.get(key);
        },
        [params],
    );

    const add = useCallback(
        (key: string | string[] | Record<string, string>, value?: string | string[]) => {
            if (typeof key === "string" && typeof value === "string") {
                params.set(key, value);
            } else if (isPlainObject(key)) {
                const newParams = key as Record<string, string>;
                Object.keys(newParams).forEach((k) => {
                    params.set(k, newParams[k]);
                });
            } else {
                if (!value) return;
                const keys = (Array.isArray(key) ? key : [key]) as string[];
                const values = Array.isArray(value) ? value : [value];
                keys.forEach((k, i) => {
                    params.set(k, values[i]);
                });
            }

            router.get(`${window.location.origin}${window.location.pathname}?${params.toString()}`, {
                preserveScroll: true,
            });
        },
        [params],
    );

    const remove = useCallback(
        (key: string | string[] | Record<string, string>, value?: string | string[]) => {
            if (typeof key === "string") {
                params.delete(key);
            } else if (isPlainObject(key)) {
                const newParams = key as Record<string, string>;
                Object.keys(newParams).forEach((k) => {
                    params.delete(k, newParams[k]);
                });
            } else {
                const keys = (Array.isArray(key) ? key : [key]) as string[];
                const values = Array.isArray(value) ? value : [value];
                keys.forEach((k, i) => {
                    params.delete(k, values[i]);
                });
            }

            router.visit(`${window.location.origin}${window.location.pathname}?${params.toString()}`, {
                preserveScroll: true,
            });
        },
        [params],
    );

    const toQs = useCallback((object: Record<string, string>) => {
        return Object.keys(object)
            .map((k) => `${k}=${object[k]}`)
            .join("&");
    }, []);

    return {
        entries,
        qs: params.toString(),
        toQs,
        get,
        add,
        remove,
    };
};
