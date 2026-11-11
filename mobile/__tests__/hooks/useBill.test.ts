/**
 * useBill — fetches /bills/:id?with=legislator and hands back data, loading,
 * error, and refresh.
 */

const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useBill } from "../../src/hooks/useBill";

describe("useBill", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    test("fetches /bills/:id?with=legislator on mount and exposes data", async () => {
        const payload = { bill: { id: 42, title: "Open Records" }, sponsor: { full_name: "Alice" } };
        mockGet.mockResolvedValue(payload);

        const { result } = renderHook(() => useBill(42));

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual(payload);
        expect(mockGet).toHaveBeenCalledWith("/bills/42?with=legislator", {
            headers: { "X-Sway-Omit-Props": "legislators,legislator_votes,public_testimony_letters" },
            signal: expect.any(AbortSignal),
        });
    });

    test("asks the server to omit the legislators, their votes and the testimony letters, but not the reader's districts", async () => {
        mockGet.mockResolvedValue({ bill: { id: 5, title: "x" } });
        renderHook(() => useBill(5));
        await waitFor(() => expect(mockGet).toHaveBeenCalled());

        const header = mockGet.mock.calls[0][1].headers["X-Sway-Omit-Props"] as string;
        expect(header.split(",").sort()).toEqual(["legislator_votes", "legislators", "public_testimony_letters"]);
    });

    test("surfaces errors from apiClient", async () => {
        mockGet.mockRejectedValue(new Error("boom"));
        const { result } = renderHook(() => useBill(7));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBeInstanceOf(Error);
        expect(result.current.data).toBeNull();
    });

    test("refresh() triggers a new fetch and aborts previous in-flight fetch on unmount", async () => {
        mockGet.mockResolvedValue({ bill: { id: 1, title: "x" } });
        const { result, unmount } = renderHook(() => useBill(1));
        await waitFor(() => expect(result.current.loading).toBe(false));
        mockGet.mockClear();
        mockGet.mockResolvedValue({ bill: { id: 1, title: "y" } });

        await act(async () => {
            await result.current.refresh();
        });
        expect(mockGet).toHaveBeenCalledWith("/bills/1?with=legislator", {
            headers: { "X-Sway-Omit-Props": "legislators,legislator_votes,public_testimony_letters" },
            signal: expect.any(AbortSignal),
        });
        const signal = mockGet.mock.calls[0][1].signal as AbortSignal;
        expect(signal.aborted).toBe(false);
        expect((result.current.data?.bill as { title: string }).title).toBe("y");

        unmount();
        expect(signal.aborted).toBe(true);
    });
});
