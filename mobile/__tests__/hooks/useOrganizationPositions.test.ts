/**
 * useOrganizationPositions — written to pass against the finished hook.
 */

const mockGet = jest.fn();
const mockPost = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...args),
        post: (...args: unknown[]) => mockPost(...args),
    },
}));

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useOrganizationPositions } from "../../src/hooks/useOrganizationPositions";

describe("useOrganizationPositions", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPost.mockReset();
    });

    test("module exports useOrganizationPositions", () => {
        expect(useOrganizationPositions).toBeDefined();
    });

    test("list path: fetches membership endpoint and populates positions", async () => {
        const payload = {
            membership: {
                positions: [
                    {
                        id: 1,
                        support: "FOR",
                        summary: "We support",
                        bill: { id: 10, external_id: "HB001", title: "Bill 1" },
                    },
                ],
            },
        };
        mockGet.mockResolvedValue(payload);

        const { result } = renderHook(() => useOrganizationPositions(5, 12));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.positions).toHaveLength(1);
        expect(result.current.positions[0].id).toBe(1);
        expect(result.current.error).toBeNull();
        expect(mockGet).toHaveBeenCalledWith("/organizations/5/memberships/12");
    });

    test("starts with loading=true and positions=[]", () => {
        mockGet.mockResolvedValue({ membership: { positions: [] } });
        const { result } = renderHook(() => useOrganizationPositions(5, 12));
        expect(result.current.loading).toBe(true);
        expect(result.current.positions).toEqual([]);
    });

    test("propose path: POSTs to orgPositions route and triggers refresh", async () => {
        mockGet.mockResolvedValue({ membership: { positions: [] } });
        mockPost.mockResolvedValue({ success: true });

        const { result } = renderHook(() => useOrganizationPositions(5, 12));
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => {
            await result.current.propose({
                bill_id: 10,
                support: "FOR",
                summary: "Test summary",
            });
        });

        expect(mockPost).toHaveBeenCalledWith(
            "/organizations/5/positions",
            expect.objectContaining({ bill_id: 10, support: "FOR" }),
        );
        expect(mockGet.mock.calls.length).toBeGreaterThanOrEqual(2);
    });

    test("surfaces errors from apiClient", async () => {
        mockGet.mockRejectedValue(new Error("forbidden"));
        const { result } = renderHook(() => useOrganizationPositions(5, 12));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBeInstanceOf(Error);
    });
});
