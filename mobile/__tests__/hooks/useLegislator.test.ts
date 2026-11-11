const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import { act, renderHook, waitFor } from "@testing-library/react-native";
import { ApiRequestError } from "../../src/api/errors";
import { useLegislator } from "../../src/hooks/useLegislator";

interface Deferred<T> {
    promise: Promise<T>;
    resolve: (value: T) => void;
    reject: (reason: unknown) => void;
}

function deferred<T>(): Deferred<T> {
    let resolve!: (value: T) => void;
    let reject!: (reason: unknown) => void;
    const promise = new Promise<T>((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
}

function signalOf(callIndex: number): AbortSignal {
    return (mockGet.mock.calls[callIndex][1] as { signal: AbortSignal }).signal;
}

describe("useLegislator", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    test("unwraps a { legislator } response from /legislators/:id", async () => {
        mockGet.mockResolvedValue({ legislator: { id: 7, full_name: "Ada" } });
        const { result } = renderHook(() => useLegislator(7));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual({ id: 7, full_name: "Ada" });
        expect(result.current.error).toBeNull();
        expect(mockGet).toHaveBeenCalledWith("/legislators/7", { signal: expect.any(AbortSignal) });
    });

    test("accepts a bare legislator response", async () => {
        mockGet.mockResolvedValue({ id: 7, full_name: "Ada" });
        const { result } = renderHook(() => useLegislator(7));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual({ id: 7, full_name: "Ada" });
    });

    test("propagates request errors", async () => {
        mockGet.mockRejectedValue(new Error("boom"));
        const { result } = renderHook(() => useLegislator(7));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error?.message).toBe("boom");
        expect(result.current.data).toBeNull();
    });

    test("does not report an aborted request as an error", async () => {
        mockGet.mockRejectedValueOnce(new ApiRequestError("aborted", "request aborted by caller"));
        const { result } = renderHook(() => useLegislator(7));
        await act(async () => {
            await Promise.resolve();
        });
        expect(result.current.error).toBeNull();
    });

    test("a superseded request neither clears loading nor overwrites newer data", async () => {
        const first = deferred<unknown>();
        const second = deferred<unknown>();
        mockGet.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
        const { result } = renderHook(() => useLegislator(7));

        let refreshing!: Promise<void>;
        act(() => {
            refreshing = result.current.refresh();
        });
        expect(signalOf(0).aborted).toBe(true);

        await act(async () => {
            first.resolve({ legislator: { id: 7, full_name: "Stale" } });
            await Promise.resolve();
        });
        expect(result.current.loading).toBe(true);
        expect(result.current.data).toBeNull();

        await act(async () => {
            second.resolve({ legislator: { id: 7, full_name: "Fresh" } });
            await refreshing;
        });
        expect(result.current.loading).toBe(false);
        expect(result.current.data?.full_name).toBe("Fresh");
    });

    test("changing the id aborts the previous request", async () => {
        const first = deferred<unknown>();
        mockGet.mockReturnValueOnce(first.promise).mockResolvedValueOnce({ legislator: { id: 8 } });
        const { result, rerender } = renderHook(({ id }: { id: number }) => useLegislator(id), {
            initialProps: { id: 7 },
        });
        rerender({ id: 8 });
        expect(signalOf(0).aborted).toBe(true);
        expect(mockGet).toHaveBeenLastCalledWith("/legislators/8", { signal: expect.any(AbortSignal) });
        await waitFor(() => expect(result.current.data?.id).toBe(8));
    });

    test("unmounting aborts the in-flight request", () => {
        mockGet.mockReturnValueOnce(new Promise(() => {}));
        const { unmount } = renderHook(() => useLegislator(7));
        unmount();
        expect(signalOf(0).aborted).toBe(true);
    });

    test("refresh() refetches", async () => {
        mockGet.mockResolvedValueOnce({ legislator: { id: 7, full_name: "Old" } });
        const { result } = renderHook(() => useLegislator(7));
        await waitFor(() => expect(result.current.loading).toBe(false));
        mockGet.mockResolvedValueOnce({ legislator: { id: 7, full_name: "New" } });
        await act(async () => {
            await result.current.refresh();
        });
        expect(mockGet).toHaveBeenCalledTimes(2);
        expect(result.current.data?.full_name).toBe("New");
    });

    test("clears error immediately when refresh() is called or legislatorId changes, and hides stale data on id change", async () => {
        mockGet.mockRejectedValueOnce(new Error("initial failure"));
        const { result, rerender } = renderHook(({ id }: { id: number }) => useLegislator(id), {
            initialProps: { id: 7 },
        });
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error?.message).toBe("initial failure");

        const retry = deferred<unknown>();
        mockGet.mockReturnValueOnce(retry.promise);
        let retryPromise!: Promise<void>;
        act(() => {
            retryPromise = result.current.refresh();
        });
        expect(result.current.error).toBeNull();
        expect(result.current.loading).toBe(true);

        await act(async () => {
            retry.resolve({ legislator: { id: 7, full_name: "Recovered" } });
            await retryPromise;
        });
        expect(result.current.data?.full_name).toBe("Recovered");

        const nextIdFetch = deferred<unknown>();
        mockGet.mockReturnValueOnce(nextIdFetch.promise);
        rerender({ id: 8 });
        expect(result.current.data).toBeNull();
        expect(result.current.error).toBeNull();
        expect(result.current.loading).toBe(true);

        await act(async () => {
            nextIdFetch.resolve({ legislator: { id: 8, full_name: "Eight" } });
            await nextIdFetch.promise;
        });
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data?.full_name).toBe("Eight");
    });
});
