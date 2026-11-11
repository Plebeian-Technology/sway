/**
 * useMemberships — written to pass against the finished hook.
 */

const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useMemberships } from "../../src/hooks/useMemberships";

describe("useMemberships", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    test("fetches /users/organization_memberships and exposes { active, pending, loading, error, refresh }", async () => {
        const active = [{ id: 1, role: "standard" }];
        const pending = [{ id: 2, role: "standard" }];
        mockGet.mockResolvedValue({ memberships: active, pending_memberships: pending });

        const { result } = renderHook(() => useMemberships());

        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.active).toEqual(active);
        expect(result.current.pending).toEqual(pending);
        expect(result.current.error).toBeNull();
        expect(typeof result.current.refresh).toBe("function");
        expect(mockGet).toHaveBeenCalledWith("/users/organization_memberships");
    });

    test("defaults active and pending to empty arrays when keys are absent", async () => {
        mockGet.mockResolvedValue({});
        const { result } = renderHook(() => useMemberships());
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.active).toEqual([]);
        expect(result.current.pending).toEqual([]);
    });

    test("surfaces errors from apiClient and sets error state", async () => {
        mockGet.mockRejectedValue(new Error("network failure"));
        const { result } = renderHook(() => useMemberships());
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBeInstanceOf(Error);
        expect(result.current.active).toEqual([]);
        expect(result.current.pending).toEqual([]);
    });

    test("refresh() triggers a new fetch and updates state", async () => {
        const first = { memberships: [{ id: 1, role: "admin" }], pending_memberships: [] };
        const second = {
            memberships: [
                { id: 1, role: "admin" },
                { id: 3, role: "standard" },
            ],
            pending_memberships: [],
        };
        mockGet.mockResolvedValueOnce(first);

        const { result } = renderHook(() => useMemberships());
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.active).toHaveLength(1);

        mockGet.mockResolvedValue(second);
        await act(async () => {
            await result.current.refresh();
        });
        expect(result.current.active).toHaveLength(2);
    });
});
