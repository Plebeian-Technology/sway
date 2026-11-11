// @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]]
// @lat: [[mobile-bill-hooks#usePublicTestimonyLetters]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { ApiRequestError } from "../api/errors";
import { Routes } from "../api/routes";
import type { PublicTestimonyLetter } from "../types/bill";

export interface UsePublicTestimonyLettersOptions {
    enabled: boolean;
}

export interface UsePublicTestimonyLettersResult {
    letters: PublicTestimonyLetter[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

interface FetchState {
    billId: number;
    status: "loading" | "ready" | "error";
    letters: PublicTestimonyLetter[] | null;
    error: Error | null;
}

function parseLetters(raw: unknown): PublicTestimonyLetter[] {
    if (!Array.isArray(raw)) return [];
    return raw.flatMap((item): PublicTestimonyLetter[] => {
        if (item === null || typeof item !== "object") return [];
        const row = item as Record<string, unknown>;
        if (typeof row.position !== "number" || typeof row.body_text !== "string") return [];
        return [
            {
                position: row.position,
                label: typeof row.label === "string" ? row.label : "",
                stance: row.stance === "support" || row.stance === "oppose" ? row.stance : "neutral",
                body_text: row.body_text,
            },
        ];
    });
}

export function usePublicTestimonyLetters(
    billId: number,
    { enabled }: UsePublicTestimonyLettersOptions,
): UsePublicTestimonyLettersResult {
    const [state, setState] = useState<FetchState | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setState((prev) => ({
            billId,
            status: "loading",
            letters: prev?.billId === billId ? prev.letters : null,
            error: null,
        }));
        try {
            const res = await apiClient.get<unknown>(Routes.billPublicTestimonyLetters(billId), {
                signal: ctrl.signal,
            });
            if (ctrl.signal.aborted) return;
            setState({ billId, status: "ready", letters: parseLetters(res), error: null });
        } catch (e: unknown) {
            if (ctrl.signal.aborted || (e instanceof ApiRequestError && e.code === "aborted")) return;
            setState({
                billId,
                status: "error",
                letters: null,
                error: e instanceof Error ? e : new Error(String(e)),
            });
        }
    }, [billId]);

    useEffect(() => {
        if (!enabled) {
            setState(null);
            return undefined;
        }
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [enabled, refresh]);

    const view = enabled && state?.billId === billId ? state : null;

    return {
        letters: view?.letters ?? null,
        loading: enabled && (view === null || view.status === "loading"),
        error: view?.error ?? null,
        refresh,
    };
}
