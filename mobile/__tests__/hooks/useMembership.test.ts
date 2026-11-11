/**
 * useMembership — written to pass against the finished hook.
 */

const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useMembership } from "../../src/hooks/useMembership";

describe("useMembership", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    test("fetches /organizations/:orgId/memberships/:id and exposes { data, loading, error, refresh }", async () => {
        const payload = { membership: { id: 5, role: "admin", organization: { id: 2, name: "Test Org" } } };
        mockGet.mockResolvedValue(payload);

        const { result } = renderHook(() => useMembership(2, 5));

        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.data).toEqual(payload);
        expect(result.current.error).toBeNull();
        expect(typeof result.current.refresh).toBe("function");
        expect(mockGet).toHaveBeenCalledWith("/organizations/2/memberships/5");
    });

    test("starts with loading=true and data=null", () => {
        mockGet.mockResolvedValue({});
        const { result } = renderHook(() => useMembership(1, 1));
        expect(result.current.loading).toBe(true);
        expect(result.current.data).toBeNull();
    });

    test("surfaces errors from apiClient", async () => {
        mockGet.mockRejectedValue(new Error("not found"));
        const { result } = renderHook(() => useMembership(1, 99));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBeInstanceOf(Error);
        expect(result.current.data).toBeNull();
    });

    test("refresh() re-fetches with the same orgId and id", async () => {
        const payload1 = { membership: { id: 5, role: "standard" } };
        const payload2 = { membership: { id: 5, role: "admin" } };
        mockGet.mockResolvedValueOnce(payload1);

        const { result } = renderHook(() => useMembership(2, 5));
        await waitFor(() => expect(result.current.loading).toBe(false));

        mockGet.mockResolvedValue(payload2);
        await act(async () => {
            await result.current.refresh();
        });
        expect(mockGet).toHaveBeenLastCalledWith("/organizations/2/memberships/5");
        expect(result.current.data).toEqual(payload2);
    });

    test("re-fetches when id param changes", async () => {
        mockGet.mockResolvedValue({ membership: { id: 1, role: "standard" } });
        const { result, rerender } = renderHook(
            ({ orgId, id }: { orgId: number; id: number }) => useMembership(orgId, id),
            { initialProps: { orgId: 1, id: 1 } },
        );
        await waitFor(() => expect(result.current.loading).toBe(false));

        mockGet.mockResolvedValue({ membership: { id: 2, role: "admin" } });
        rerender({ orgId: 1, id: 2 });
        await waitFor(() => expect(mockGet).toHaveBeenCalledWith("/organizations/1/memberships/2"));
    });
});
