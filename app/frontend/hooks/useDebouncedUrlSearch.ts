import { useCallback, useEffect, useRef, useState } from "react";

import { navigateWithParams, setQueryParamCleared } from "app/frontend/sway_utils/url_navigation";

// @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
interface IDebouncedUrlSearchConfig {
    only: string[];
    resetParams?: string[];
    errorTitle: string;
    param: string;
    legacyAliases?: string[];
    debounceMs?: number;
}

// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
const DEFAULT_SEARCH_DEBOUNCE_MS = 350;

// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
export const useDebouncedUrlSearch = ({
    only,
    resetParams = [],
    errorTitle,
    param,
    legacyAliases = [],
    debounceMs = DEFAULT_SEARCH_DEBOUNCE_MS,
}: IDebouncedUrlSearchConfig) => {
    const committed = (() => {
        if (typeof window === "undefined") return "";
        const searchParams = new URLSearchParams(window.location.search);
        if (searchParams.has(param)) {
            return searchParams.get(param) ?? "";
        }
        for (const alias of legacyAliases) {
            if (searchParams.has(alias)) {
                return searchParams.get(alias) ?? "";
            }
        }
        return "";
    })();

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    const [draft, setDraft] = useState<string | null>(null);
    const [lastCommitted, setLastCommitted] = useState(committed);
    if (committed !== lastCommitted) {
        setLastCommitted(committed);
        if (draft !== null && draft.trim() === committed) {
            setDraft(null);
        }
    }
    const value = draft ?? committed;

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    useEffect(
        () => () => {
            if (timerRef.current !== null) {
                clearTimeout(timerRef.current);
            }
        },
        [],
    );

    const onChange = useCallback(
        (term: string) => {
            setDraft(term);

            if (timerRef.current !== null) clearTimeout(timerRef.current);
            timerRef.current = setTimeout(() => {
                timerRef.current = null;
                const trimmed = term.trim();
                navigateWithParams(
                    (params) => {
                        if (trimmed) {
                            params.set(param, trimmed);
                        } else {
                            setQueryParamCleared(params, param);
                        }
                        legacyAliases.forEach((alias) => {
                            if (params.has(alias)) {
                                setQueryParamCleared(params, alias);
                            } else {
                                params.delete(alias);
                            }
                        });
                    },
                    { only, resetParams, errorTitle },
                );
            }, debounceMs);
        },
        [param, legacyAliases, debounceMs, only, resetParams, errorTitle],
    );

    return { value, onChange };
};
