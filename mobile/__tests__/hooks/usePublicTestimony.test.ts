// @lat: [[mobile-bill-hooks#usePublicTestimonyLetters]]
const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import { act, renderHook, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../src/api/errors";
import { usePublicTestimonyLetters } from "../../src/hooks/usePublicTestimony";
import type { PublicTestimonyLetter } from "../../src/types/bill";

const LETTERS: PublicTestimonyLetter[] = [
    {
        position: 1,
        label: "Constituent Letter #1",
        stance: "support",
        body_text: "I strongly support this bill for clean neighborhood air.",
    },
    {
        position: 2,
        label: "Constituent Letter #2",
        stance: "oppose",
        body_text: "I oppose the fee increases mandated by this bill.",
    },
];

describe("usePublicTestimonyLetters", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    test("makes no request on mount while disabled", async () => {
        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: false }));

        await act(async () => {});
        expect(mockGet).not.toHaveBeenCalled();
        expect(result.current.letters).toBeNull();
        expect(result.current.loading).toBe(false);
        expect(result.current.error).toBeNull();
    });

    test("fetches the letters from their own route and exposes them", async () => {
        mockGet.mockResolvedValue(LETTERS);

        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.letters).toEqual(LETTERS);
        expect(result.current.error).toBeNull();
        expect(mockGet).toHaveBeenCalledTimes(1);
        expect(mockGet).toHaveBeenCalledWith("/bills/42/public_testimony_letters", {
            signal: expect.any(AbortSignal),
        });
    });

    test("sends no omit-props header", async () => {
        mockGet.mockResolvedValue([]);

        const { result } = renderHook(() => usePublicTestimonyLetters(7, { enabled: true }));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(mockGet.mock.calls[0][1]).not.toHaveProperty("headers");
    });

    test("reports loading from the first enabled render, before any response", async () => {
        let resolve: (value: unknown) => void = () => {};
        mockGet.mockReturnValue(
            new Promise((r) => {
                resolve = r;
            }),
        );

        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));
        expect(result.current.loading).toBe(true);
        expect(result.current.letters).toBeNull();

        await act(async () => {
            resolve(LETTERS);
        });
        expect(result.current.loading).toBe(false);
        expect(result.current.letters).toEqual(LETTERS);
    });

    test("treats a null body, the signed-out answer, as an empty list", async () => {
        mockGet.mockResolvedValue(null);

        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.letters).toEqual([]);
        expect(result.current.error).toBeNull();
    });

    test("drops malformed rows and coerces an unknown stance to neutral", async () => {
        mockGet.mockResolvedValue([
            { position: 3, label: "Constituent Letter #3", stance: "mixed", body_text: "Kept as neutral." },
            { position: "4", label: "bad position", stance: "support", body_text: "dropped" },
            { position: 5, label: "no body", stance: "support" },
            null,
            "text",
        ]);

        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.letters).toEqual([
            { position: 3, label: "Constituent Letter #3", stance: "neutral", body_text: "Kept as neutral." },
        ]);
    });

    test("surfaces request failures as an error with no letters", async () => {
        mockGet.mockRejectedValue(new Error("boom"));

        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBeInstanceOf(Error);
        expect(result.current.letters).toBeNull();
    });

    test("ignores an aborted request instead of reporting an error", async () => {
        mockGet.mockRejectedValue(new ApiRequestError("aborted", "request aborted by caller"));

        const { result, unmount } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));
        await act(async () => {});

        expect(result.current.error).toBeNull();
        unmount();
    });

    test("refresh() requests the letters again and clears a previous error", async () => {
        mockGet.mockRejectedValueOnce(new Error("offline"));
        const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));
        await waitFor(() => expect(result.current.error).not.toBeNull());

        mockGet.mockResolvedValue(LETTERS);
        await act(async () => {
            await result.current.refresh();
        });

        expect(mockGet).toHaveBeenCalledTimes(2);
        expect(result.current.error).toBeNull();
        expect(result.current.letters).toEqual(LETTERS);
    });

    test("aborts the in-flight request and drops the letters when enabled turns false", async () => {
        mockGet.mockResolvedValue(LETTERS);
        const { result, rerender } = renderHook(
            ({ enabled }: { enabled: boolean }) => usePublicTestimonyLetters(42, { enabled }),
            { initialProps: { enabled: true } },
        );
        await waitFor(() => expect(result.current.letters).toEqual(LETTERS));
        const signal = mockGet.mock.calls[0][1].signal as AbortSignal;

        rerender({ enabled: false });

        expect(signal.aborted).toBe(true);
        expect(result.current.letters).toBeNull();
        expect(result.current.loading).toBe(false);
    });

    test("fetches again each time it is re-enabled", async () => {
        mockGet.mockResolvedValue(LETTERS);
        const { result, rerender } = renderHook(
            ({ enabled }: { enabled: boolean }) => usePublicTestimonyLetters(42, { enabled }),
            { initialProps: { enabled: true } },
        );
        await waitFor(() => expect(result.current.letters).toEqual(LETTERS));

        rerender({ enabled: false });
        rerender({ enabled: true });
        await waitFor(() => expect(result.current.letters).toEqual(LETTERS));

        expect(mockGet).toHaveBeenCalledTimes(2);
    });

    test("never serves one bill's letters for another bill", async () => {
        mockGet.mockResolvedValueOnce(LETTERS);
        const { result, rerender } = renderHook(
            ({ billId }: { billId: number }) => usePublicTestimonyLetters(billId, { enabled: true }),
            { initialProps: { billId: 42 } },
        );
        await waitFor(() => expect(result.current.letters).toEqual(LETTERS));

        let resolve: (value: unknown) => void = () => {};
        mockGet.mockReturnValueOnce(
            new Promise((r) => {
                resolve = r;
            }),
        );
        rerender({ billId: 43 });

        expect(result.current.letters).toBeNull();
        expect(result.current.loading).toBe(true);
        expect(mockGet).toHaveBeenLastCalledWith("/bills/43/public_testimony_letters", expect.anything());

        await act(async () => {
            resolve([]);
        });
        expect(result.current.letters).toEqual([]);
    });

    test("aborts on unmount", async () => {
        mockGet.mockResolvedValue(LETTERS);
        const { result, unmount } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));
        await waitFor(() => expect(result.current.loading).toBe(false));
        const signal = mockGet.mock.calls[0][1].signal as AbortSignal;

        unmount();

        expect(signal.aborted).toBe(true);
    });

    test("does not poll", async () => {
        jest.useFakeTimers();
        try {
            mockGet.mockResolvedValue(LETTERS);
            const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));
            await waitFor(() => expect(result.current.loading).toBe(false));

            await act(async () => {
                jest.advanceTimersByTime(120_000);
            });

            expect(mockGet).toHaveBeenCalledTimes(1);
        } finally {
            jest.useRealTimers();
        }
    });

    test("writes nothing to the console when a request fails", async () => {
        const spies = (["log", "info", "warn", "error", "debug"] as const).map((level) =>
            jest.spyOn(console, level).mockImplementation(() => {}),
        );
        try {
            mockGet.mockRejectedValue(new Error("boom"));
            const { result } = renderHook(() => usePublicTestimonyLetters(42, { enabled: true }));
            await waitFor(() => expect(result.current.loading).toBe(false));

            for (const spy of spies) expect(spy).not.toHaveBeenCalled();
        } finally {
            for (const spy of spies) spy.mockRestore();
        }
    });
});
