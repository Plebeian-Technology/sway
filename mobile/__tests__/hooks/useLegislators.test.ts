// @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]

const mockGet = jest.fn(async (_path: string): Promise<Record<string, unknown>> => ({ legislators: [] }));
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...(args as [string])),
    },
}));

const mockCacheGet = jest.fn(async (_localeId: number): Promise<unknown[]> => []);
const mockCacheSet = jest.fn(async (_localeId: number, _legs: unknown[]) => {});
jest.mock("../../src/cache/legislatorCache", () => ({
    get: (...args: unknown[]) => mockCacheGet(...(args as [number])),
    set: (...args: unknown[]) => mockCacheSet(...(args as [number, unknown[]])),
    clear: jest.fn(async () => {}),
}));

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useLegislators } from "../../src/hooks/useLegislators";

const BALTIMORE = { sessions: [{ session_label: "2021–2023 Baltimore", entries: [] }] };
const CONGRESS = { sessions: [{ session_label: "117th Congress", entries: [] }] };

const historyFor = (path: string) => (path.includes("sway_locale_id=3") ? CONGRESS : BALTIMORE);

describe("useLegislators history scoping", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockGet.mockImplementation(async (path: string) => ({ legislators: [], history: historyFor(path) }));
    });

    it("returns the history it fetched for the active locale", async () => {
        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => {
            await result.current.fetchHistory();
        });

        expect(result.current.history).toEqual(BALTIMORE);
    });

    it("reports no history for a locale it has not been fetched for", async () => {
        const { result, rerender } = renderHook((props: { swayLocaleId: number }) => useLegislators(props), {
            initialProps: { swayLocaleId: 1 },
        });
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => {
            await result.current.fetchHistory();
        });
        expect(result.current.history).toEqual(BALTIMORE);

        rerender({ swayLocaleId: 3 });

        // Switching is enough to clear it. Showing Baltimore's terms under a
        // Congress heading is worse than showing nothing.
        expect(result.current.history).toBeNull();
        await waitFor(() => expect(result.current.loading).toBe(false));
    });

    it("fetches the locale it is handed, not the one it was rendered with", async () => {
        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        // The code handling the switch calls this before React re-renders with
        // the new locale, so calling it with no argument would ask for the old one.
        await act(async () => {
            await result.current.fetchHistory(3);
        });

        expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("sway_locale_id=3"));
    });

    it("discards a response that lands after the reader has moved on", async () => {
        const { result, rerender } = renderHook((props: { swayLocaleId: number }) => useLegislators(props), {
            initialProps: { swayLocaleId: 1 },
        });
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => {
            const inFlight = result.current.fetchHistory();
            rerender({ swayLocaleId: 3 });
            await inFlight;
        });

        expect(result.current.history).toBeNull();
    });

    it("does not carry one locale's history error onto the next", async () => {
        const { result, rerender } = renderHook((props: { swayLocaleId: number }) => useLegislators(props), {
            initialProps: { swayLocaleId: 1 },
        });
        await waitFor(() => expect(result.current.loading).toBe(false));

        mockGet.mockRejectedValueOnce(new Error("boom"));
        await act(async () => {
            await result.current.fetchHistory();
        });
        expect(result.current.historyError).toBeInstanceOf(Error);

        rerender({ swayLocaleId: 3 });

        expect(result.current.historyError).toBeNull();
        await waitFor(() => expect(result.current.loading).toBe(false));
    });
});

// @lat: [[registration-dead-ends#The dead ends in registration#An empty list says which kind of empty it is]]
describe("useLegislators waiting for the new term", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    it("carries the server's answer through", async () => {
        mockGet.mockImplementation(async () => ({ legislators: [], waiting_for_new_term: true }));

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.data).toEqual([]);
        expect(result.current.waitingForNewTerm).toBe(true);
    });

    it("is false when the server does not say so", async () => {
        mockGet.mockImplementation(async () => ({ legislators: [] }));

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.waitingForNewTerm).toBe(false);
    });

    // The server can also answer with a plain array, which carries no such flag.
    it("is false when the server answers with a plain list", async () => {
        mockGet.mockImplementation(async () => [] as unknown as Record<string, unknown>);

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.waitingForNewTerm).toBe(false);
    });
});

describe("useLegislators SQLite caching", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockCacheGet.mockReset();
        mockCacheSet.mockReset();
        mockCacheGet.mockResolvedValue([]);
    });

    it("hydrates data from cache immediately on cache hit", async () => {
        const cachedLeg = { id: 10, full_name: "Cached Rep" };
        let resolveApi: (value: Record<string, unknown>) => void;
        const apiPromise = new Promise<Record<string, unknown>>((resolve) => {
            resolveApi = resolve;
        });
        mockCacheGet.mockResolvedValueOnce([{ legislator: cachedLeg, cachedAt: Date.now() }]);
        mockGet.mockReturnValueOnce(apiPromise);

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));

        await waitFor(() => expect(result.current.data).toEqual([cachedLeg]));
        expect(result.current.loading).toBe(true);

        await act(async () => {
            resolveApi!({ legislators: [cachedLeg, { id: 11, full_name: "Fresh Rep" }] });
            await apiPromise;
        });

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toHaveLength(2);
    });

    it("writes fresh legislators to cache on successful fetch", async () => {
        const fresh = [{ id: 42, full_name: "Elected Rep" }];
        mockGet.mockResolvedValueOnce({ legislators: fresh });

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 2 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.data).toEqual(fresh);
        expect(mockCacheSet).toHaveBeenCalledWith(2, fresh);
    });

    it("retains cached data on network error and does not query SQLite cache again on a subsequent offline refresh", async () => {
        const cachedLeg = { id: 7, full_name: "Offline Rep" };
        mockCacheGet.mockResolvedValueOnce([{ legislator: cachedLeg, cachedAt: Date.now() }]);
        mockGet.mockRejectedValueOnce(new Error("network failure"));

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.error).toBeInstanceOf(Error);
        expect(result.current.data).toEqual([cachedLeg]);
        expect(mockCacheGet).toHaveBeenCalledTimes(1);

        mockGet.mockRejectedValueOnce(new Error("still offline"));
        await act(async () => {
            await result.current.refresh();
        });

        expect(mockCacheGet).toHaveBeenCalledTimes(1);
        expect(result.current.data).toEqual([cachedLeg]);
        expect(result.current.error).toBeInstanceOf(Error);
    });

    it("is resilient to SQLite errors during get and set", async () => {
        mockCacheGet.mockRejectedValueOnce(new Error("disk error"));
        mockCacheSet.mockRejectedValueOnce(new Error("disk error"));
        const fresh = [{ id: 99, full_name: "Resilient Rep" }];
        mockGet.mockResolvedValueOnce({ legislators: fresh });

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.error).toBeNull();
        expect(result.current.data).toEqual(fresh);
    });

    it("skips SQLite cache operations when swayLocaleId is omitted", async () => {
        mockGet.mockResolvedValueOnce({ legislators: [{ id: 1, full_name: "Default Rep" }] });

        const { result } = renderHook(() => useLegislators());
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(mockCacheGet).not.toHaveBeenCalled();
        expect(mockCacheSet).not.toHaveBeenCalled();
    });

    it("discards an in-flight refresh from a previous locale that resolves after switching swayLocaleId", async () => {
        let resolveLocale1: (value: Record<string, unknown>) => void;
        const locale1Promise = new Promise<Record<string, unknown>>((resolve) => {
            resolveLocale1 = resolve;
        });
        const locale2Rep = { id: 20, full_name: "Locale 2 Rep" };
        mockGet.mockImplementation((path: string) => {
            if (path.includes("sway_locale_id=1")) return locale1Promise;
            return Promise.resolve({ legislators: [locale2Rep] });
        });

        const { result, rerender } = renderHook((props: { swayLocaleId: number }) => useLegislators(props), {
            initialProps: { swayLocaleId: 1 },
        });

        rerender({ swayLocaleId: 2 });
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual([locale2Rep]);

        await act(async () => {
            resolveLocale1!({ legislators: [{ id: 10, full_name: "Stale Locale 1 Rep" }] });
            await locale1Promise;
        });

        expect(result.current.data).toEqual([locale2Rep]);
        expect(mockCacheSet).not.toHaveBeenCalledWith(1, expect.anything());
    });

    it("clears previous locale legislators when switching to a locale with an empty cache and failing network", async () => {
        const locale1Rep = { id: 10, full_name: "Locale 1 Rep" };
        mockGet.mockResolvedValueOnce({ legislators: [locale1Rep] });

        const { result, rerender } = renderHook((props: { swayLocaleId: number }) => useLegislators(props), {
            initialProps: { swayLocaleId: 1 },
        });
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual([locale1Rep]);

        mockCacheGet.mockResolvedValueOnce([]);
        mockGet.mockRejectedValueOnce(new Error("offline"));

        rerender({ swayLocaleId: 2 });
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.data).toEqual([]);
        expect(result.current.error).toBeInstanceOf(Error);
    });

    it("does not overwrite fresh in-memory data with stale SQLite cache rows on a subsequent refresh poll", async () => {
        const freshRep = { id: 10, full_name: "Fresh Rep" };
        const staleCachedRep = { id: 10, full_name: "Stale Cached Rep" };
        mockGet.mockResolvedValueOnce({ legislators: [freshRep] });

        const { result } = renderHook(() => useLegislators({ swayLocaleId: 1 }));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual([freshRep]);
        expect(mockCacheGet).toHaveBeenCalledTimes(1);

        mockCacheGet.mockResolvedValueOnce([{ legislator: staleCachedRep, cachedAt: Date.now() }]);
        mockGet.mockRejectedValueOnce(new Error("poll failed"));

        await act(async () => {
            await result.current.refresh();
        });

        expect(mockCacheGet).toHaveBeenCalledTimes(1);
        expect(result.current.data).toEqual([freshRep]);
        expect(result.current.error).toBeInstanceOf(Error);
    });
});
