// @lat: [[mobile-jest-first-pass-test-notes#usePendingChanges.test.ts]]

const mockGet = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

import { Alert } from "react-native";
import { renderHook, waitFor, act } from "@testing-library/react-native";
import { usePendingChanges } from "../../src/hooks/usePendingChanges";
import { ApiRequestError } from "../../src/api/errors";

describe("usePendingChanges", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPatch.mockReset();
        mockDelete.mockReset();
    });

    test("module exports usePendingChanges", () => {
        expect(usePendingChanges).toBeDefined();
    });

    test("list path: fetches membership and populates changes", async () => {
        const payload = {
            membership: {
                pending_changes: [
                    {
                        id: 3,
                        organization_bill_position_id: 7,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old",
                        new_summary: "New",
                        created_at: "2026-04-27T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
            },
        };
        mockGet.mockResolvedValue(payload);

        const { result } = renderHook(() => usePendingChanges(5, 12));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.changes).toHaveLength(1);
        expect(result.current.changes[0].id).toBe(3);
        expect(result.current.error).toBeNull();
        expect(mockGet).toHaveBeenCalledWith("/organizations/5/memberships/12");
    });

    test("starts with loading=true and changes=[]", () => {
        mockGet.mockResolvedValue({ membership: { pending_changes: [] } });
        const { result } = renderHook(() => usePendingChanges(5, 12));
        expect(result.current.loading).toBe(true);
        expect(result.current.changes).toEqual([]);
    });

    test("approve path: PATCHes pendingChange route with no body and refreshes", async () => {
        // The controller ignores the request body. Sending the PATCH at all, as
        // an admin, is what counts as approval, so the hook sends `undefined` as
        // the body. The check below looks only at the path, so tightening the
        // controller's parameter handling later will not break this test.
        mockGet.mockResolvedValue({ membership: { pending_changes: [] } });
        mockPatch.mockResolvedValue({ success: true });

        const { result } = renderHook(() => usePendingChanges(5, 12));
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => {
            await result.current.approve(3);
        });

        expect(mockPatch).toHaveBeenCalledWith("/organizations/5/position_changes/3", undefined);
        expect(mockGet.mock.calls.length).toBeGreaterThanOrEqual(2);
    });

    test("surfaces errors from apiClient", async () => {
        mockGet.mockRejectedValue(new Error("not found"));
        const { result } = renderHook(() => usePendingChanges(5, 12));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBeInstanceOf(Error);
    });

    describe("reject mutation", () => {
        test("DELETEs pendingChange route and refreshes on success", async () => {
            mockGet.mockResolvedValue({ membership: { pending_changes: [] } });
            mockDelete.mockResolvedValue(undefined);

            const { result } = renderHook(() => usePendingChanges(5, 12));
            await waitFor(() => expect(result.current.loading).toBe(false));

            await act(async () => {
                await result.current.reject(7);
            });

            expect(mockDelete).toHaveBeenCalledWith("/organizations/5/position_changes/7");
            // The list is fetched twice: once on mount, once after the reject.
            expect(mockGet.mock.calls.length).toBeGreaterThanOrEqual(2);
        });

        test("re-throws ApiRequestError(422) so callers surface 'Change is already finalized.' via Alert.alert", async () => {
            const finalizedError = new ApiRequestError(
                "already_finalized",
                "Change is already finalized.",
                undefined,
                422,
            );
            mockGet.mockResolvedValue({ membership: { pending_changes: [] } });
            mockDelete.mockRejectedValueOnce(finalizedError);

            const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});

            const { result } = renderHook(() => usePendingChanges(5, 12));
            await waitFor(() => expect(result.current.loading).toBe(false));

            // Do exactly what PendingChangesList's onReject does: catch, then alert
            await act(async () => {
                await result.current.reject(99).catch((err: unknown) => {
                    const message = err instanceof Error ? err.message : "Could not reject change.";
                    Alert.alert("Reject failed", message);
                });
            });

            expect(alertSpy).toHaveBeenCalledWith("Reject failed", "Change is already finalized.");
            expect(mockDelete).toHaveBeenCalledTimes(1);

            alertSpy.mockRestore();
        });

        test("clears busy in finally even when reject rejects", async () => {
            const finalizedError = new ApiRequestError(
                "already_finalized",
                "Change is already finalized.",
                undefined,
                422,
            );
            mockGet.mockResolvedValue({ membership: { pending_changes: [] } });
            mockDelete.mockRejectedValueOnce(finalizedError);

            const { result } = renderHook(() => usePendingChanges(5, 12));
            await waitFor(() => expect(result.current.loading).toBe(false));

            await act(async () => {
                await result.current.reject(99).catch(() => {
                    /* ignore the error here — this test is only about the busy flag */
                });
            });

            expect(result.current.busy).toBe(false);
        });
    });
});
