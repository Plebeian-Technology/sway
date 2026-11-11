const mockGet = jest.fn();
const mockPatch = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...(args as [string])),
        patch: (...args: unknown[]) => mockPatch(...(args as [string, unknown])),
    },
}));

import { renderHook, act, waitFor } from "@testing-library/react-native";
import { NOTIFICATION_PREF_KEYS, useNotificationPrefs } from "../../src/hooks/useNotificationPrefs";

describe("useNotificationPrefs", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPatch.mockReset();
        mockGet.mockResolvedValue([
            { key: "botm_announcement", enabled: true },
            { key: "legislator_voted", enabled: false },
            { key: "vote_window_closing", enabled: false },
            { key: "org_position_taken", enabled: false },
        ]);
        mockPatch.mockResolvedValue(undefined);
    });

    test("loads 4 D-37 prefs on mount with canonical botm_announcement", async () => {
        const { result } = renderHook(() => useNotificationPrefs());
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.prefs.map((p) => p.key)).toEqual([...NOTIFICATION_PREF_KEYS]);
        expect(NOTIFICATION_PREF_KEYS).toContain("botm_announcement");
        expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(true);
    });

    test("toggle optimistically updates and PATCHes the row", async () => {
        const { result } = renderHook(() => useNotificationPrefs());
        await waitFor(() => expect(result.current.loading).toBe(false));
        await act(async () => {
            await result.current.toggle("legislator_voted", true);
        });
        expect(result.current.prefs.find((p) => p.key === "legislator_voted")?.enabled).toBe(true);
        expect(mockPatch).toHaveBeenCalledWith("/api/v1/notification_preferences/legislator_voted", { enabled: true });
    });

    test("toggle rolls back on PATCH failure and re-throws", async () => {
        mockPatch.mockRejectedValueOnce(new Error("server 500"));
        const { result } = renderHook(() => useNotificationPrefs());
        await waitFor(() => expect(result.current.loading).toBe(false));
        await act(async () => {
            await expect(result.current.toggle("botm_announcement", false)).rejects.toThrow("server 500");
        });
        expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(true);
    });

    test("refresh re-fetches from server", async () => {
        const { result } = renderHook(() => useNotificationPrefs());
        await waitFor(() => expect(result.current.loading).toBe(false));
        mockGet.mockResolvedValueOnce([
            { key: "botm_announcement", enabled: false },
            { key: "legislator_voted", enabled: true },
            { key: "vote_window_closing", enabled: true },
            { key: "org_position_taken", enabled: true },
        ]);
        await act(async () => {
            await result.current.refresh();
        });
        expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(false);
        expect(result.current.prefs.find((p) => p.key === "legislator_voted")?.enabled).toBe(true);
    });
});
