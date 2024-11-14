import { router } from "@inertiajs/react";
import { isPlainObject } from "lodash";
import { useCallback, useMemo } from "react";

export interface IParams {
    entries: Record<string, string>;
    qs: string;
    get: (key: string) => string | null;
    add: (key: string | string[] | Record<string, string>, value?: string | string[]) => void;
    remove: (key: string | string[] | Record<string, string>, value?: string | string[]) => void;
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
            if (isPlainObject(key)) {
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

            router.get(`${window.location.origin}${window.location.pathname}?${params.toString()}`);
        },
        [params],
    );

    const remove = useCallback(
        (key: string | string[] | Record<string, string>, value?: string | string[]) => {
            if (isPlainObject(key)) {
                const newParams = key as Record<string, string>;
                Object.keys(newParams).forEach((k) => {
                    params.delete(k, newParams[k]);
                });
            } else {
                if (!value) return;
                const keys = (Array.isArray(key) ? key : [key]) as string[];
                const values = Array.isArray(value) ? value : [value];
                keys.forEach((k, i) => {
                    params.delete(k, values[i]);
                });
            }

            router.get(`${window.location.origin}${window.location.pathname}?${params.toString()}`);
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
