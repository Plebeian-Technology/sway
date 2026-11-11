// @lat: [[surfaces#Delivery surfaces#The /api/v1 mobile API]]
const mockGet = jest.fn();
const mockPatch = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...(args as [string])),
        patch: (...args: unknown[]) => mockPatch(...(args as [string, unknown])),
    },
}));

import { renderHook, act, waitFor } from "@testing-library/react-native";
import { useNotificationPrefs } from "../../src/hooks/useNotificationPrefs";

describe("useNotificationPrefs - Empirical Adversarial Challenge", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPatch.mockReset();
        mockPatch.mockResolvedValue(undefined);
    });

    describe("1. API Key Presence and Defaults", () => {
        test("New server: returns ONLY botm_announcement: true -> yields botm_announcement: true", async () => {
            mockGet.mockResolvedValueOnce([
                { key: "botm_announcement", enabled: true, updated_at: "2026-10-02T00:00:00Z" },
            ]);
            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            const botm = result.current.prefs.find((p) => p.key === "botm_announcement");
            expect(botm?.enabled).toBe(true);
            expect(botm?.updated_at).toBe("2026-10-02T00:00:00Z");
        });

        test("New server: returns ONLY botm_announcement: false -> yields botm_announcement: false", async () => {
            mockGet.mockResolvedValueOnce([
                { key: "botm_announcement", enabled: false, updated_at: "2026-10-02T00:00:00Z" },
            ]);
            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            const botm = result.current.prefs.find((p) => p.key === "botm_announcement");
            expect(botm?.enabled).toBe(false);
            expect(botm?.updated_at).toBe("2026-10-02T00:00:00Z");
        });

        test("Neither key present: empty array [] -> defaults to botm enabled: true, other keys false", async () => {
            mockGet.mockResolvedValueOnce([]);
            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            expect(result.current.prefs).toEqual([
                { key: "botm_announcement", enabled: true },
                { key: "legislator_voted", enabled: false },
                { key: "vote_window_closing", enabled: false },
                { key: "org_position_taken", enabled: false },
            ]);
        });

        test("Neither key present: only unrelated preferences -> botm defaults to enabled: true", async () => {
            mockGet.mockResolvedValueOnce([
                { key: "legislator_voted", enabled: true, updated_at: "2026-10-01T00:00:00Z" },
            ]);
            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            const botm = result.current.prefs.find((p) => p.key === "botm_announcement");
            expect(botm?.enabled).toBe(true);

            const legVoted = result.current.prefs.find((p) => p.key === "legislator_voted");
            expect(legVoted?.enabled).toBe(true);

            const closing = result.current.prefs.find((p) => p.key === "vote_window_closing");
            expect(closing?.enabled).toBe(false);
        });
    });

    describe("2. Toggle Behavior: Optimistic Update, Endpoint Targeting, Rollback", () => {
        test("optimistic update from true to false, calls PATCH /api/v1/notification_preferences/botm_announcement", async () => {
            mockGet.mockResolvedValueOnce([{ key: "botm_announcement", enabled: true }]);
            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(true);

            await act(async () => {
                await result.current.toggle("botm_announcement", false);
            });

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(false);
            expect(mockPatch).toHaveBeenCalledWith("/api/v1/notification_preferences/botm_announcement", {
                enabled: false,
            });
        });

        test("optimistic update from false to true, calls PATCH /api/v1/notification_preferences/botm_announcement", async () => {
            mockGet.mockResolvedValueOnce([{ key: "botm_announcement", enabled: false }]);
            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(false);

            await act(async () => {
                await result.current.toggle("botm_announcement", true);
            });

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(true);
            expect(mockPatch).toHaveBeenCalledWith("/api/v1/notification_preferences/botm_announcement", {
                enabled: true,
            });
        });

        test("rolls back to false if toggle to true fails with network error", async () => {
            mockGet.mockResolvedValueOnce([{ key: "botm_announcement", enabled: false }]);
            mockPatch.mockRejectedValueOnce(new Error("Network Error"));

            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(false);

            await act(async () => {
                await expect(result.current.toggle("botm_announcement", true)).rejects.toThrow("Network Error");
            });

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(false);
        });

        test("rolls back to true if toggle to false fails with server 500", async () => {
            mockGet.mockResolvedValueOnce([{ key: "botm_announcement", enabled: true }]);
            mockPatch.mockRejectedValueOnce(new Error("500 Internal Server Error"));

            const { result } = renderHook(() => useNotificationPrefs());
            await waitFor(() => expect(result.current.loading).toBe(false));

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(true);

            await act(async () => {
                await expect(result.current.toggle("botm_announcement", false)).rejects.toThrow(
                    "500 Internal Server Error",
                );
            });

            expect(result.current.prefs.find((p) => p.key === "botm_announcement")?.enabled).toBe(true);
        });
    });
});
