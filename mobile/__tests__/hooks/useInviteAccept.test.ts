// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]

const mockPost = jest.fn();
const mockDelete = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockPost(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

import { renderHook, act } from "@testing-library/react-native";
import { useInviteAccept, InviteRefreshError } from "../../src/hooks/useInviteAccept";

describe("useInviteAccept", () => {
    beforeEach(() => {
        mockPost.mockReset();
        mockDelete.mockReset();
    });

    describe("accept()", () => {
        test("POSTs to /organizations/:orgId/membership_invites/:id/accept", async () => {
            mockPost.mockResolvedValue({});
            const { result } = renderHook(() => useInviteAccept({}));

            await act(async () => {
                await result.current.accept(10, 99);
            });

            expect(mockPost).toHaveBeenCalledWith("/organizations/10/membership_invites/99/accept", undefined);
        });

        test("calls refresh callback after successful accept", async () => {
            mockPost.mockResolvedValue({});
            const refresh = jest.fn().mockResolvedValue(undefined);
            const { result } = renderHook(() => useInviteAccept({ refresh }));

            await act(async () => {
                await result.current.accept(10, 99);
            });

            expect(refresh).toHaveBeenCalledTimes(1);
        });

        test("does not call refresh when accept POST fails", async () => {
            const err = new Error("server error");
            mockPost.mockRejectedValue(err);
            const refresh = jest.fn().mockResolvedValue(undefined);
            const { result } = renderHook(() => useInviteAccept({ refresh }));

            await act(async () => {
                await result.current.accept(10, 99).catch(() => {});
            });

            expect(refresh).not.toHaveBeenCalled();
        });

        test("sets error state on accept failure", async () => {
            const err = new Error("network failure");
            mockPost.mockRejectedValue(err);
            const { result } = renderHook(() => useInviteAccept({}));

            await act(async () => {
                await result.current.accept(10, 99).catch(() => {});
            });

            expect(result.current.error).toBeInstanceOf(Error);
            expect(result.current.error?.message).toBe("network failure");
        });

        test("re-throws on accept failure so callers can handle it", async () => {
            mockPost.mockRejectedValue(new Error("boom"));
            const { result } = renderHook(() => useInviteAccept({}));

            await expect(
                act(async () => {
                    await result.current.accept(10, 99);
                }),
            ).rejects.toThrow("boom");
        });
    });

    describe("decline()", () => {
        test("DELETEs /organizations/:orgId/memberships/:id", async () => {
            mockDelete.mockResolvedValue({});
            const { result } = renderHook(() => useInviteAccept({}));

            await act(async () => {
                await result.current.decline(10, 99);
            });

            expect(mockDelete).toHaveBeenCalledWith("/organizations/10/memberships/99");
        });

        test("calls refresh callback after successful decline", async () => {
            mockDelete.mockResolvedValue({});
            const refresh = jest.fn().mockResolvedValue(undefined);
            const { result } = renderHook(() => useInviteAccept({ refresh }));

            await act(async () => {
                await result.current.decline(10, 99);
            });

            expect(refresh).toHaveBeenCalledTimes(1);
        });

        test("sets error state on decline failure", async () => {
            const err = new Error("decline error");
            mockDelete.mockRejectedValue(err);
            const { result } = renderHook(() => useInviteAccept({}));

            await act(async () => {
                await result.current.decline(10, 99).catch(() => {});
            });

            expect(result.current.error).toBeInstanceOf(Error);
        });

        test("re-throws on decline failure", async () => {
            mockDelete.mockRejectedValue(new Error("delete boom"));
            const { result } = renderHook(() => useInviteAccept({}));

            await expect(
                act(async () => {
                    await result.current.decline(10, 99);
                }),
            ).rejects.toThrow("delete boom");
        });
    });

    describe("error state", () => {
        test("error is null initially", () => {
            const { result } = renderHook(() => useInviteAccept({}));
            expect(result.current.error).toBeNull();
        });
    });

    describe("refresh recovery semantics", () => {
        test("does not set error state and throws InviteRefreshError when accept POST succeeds but refresh fails", async () => {
            mockPost.mockResolvedValue({});
            const refreshError = new Error("refresh failed");
            const refresh = jest.fn().mockRejectedValue(refreshError);
            const { result } = renderHook(() => useInviteAccept({ refresh }));

            let thrownError: unknown;
            await act(async () => {
                try {
                    await result.current.accept(10, 99);
                } catch (e) {
                    thrownError = e;
                }
            });

            expect(mockPost).toHaveBeenCalledWith("/organizations/10/membership_invites/99/accept", undefined);
            expect(refresh).toHaveBeenCalledTimes(1);
            expect(thrownError).toBeInstanceOf(InviteRefreshError);
            expect(result.current.error).toBeNull();
        });

        test("does not set error state and throws InviteRefreshError when decline DELETE succeeds but refresh fails", async () => {
            mockDelete.mockResolvedValue({});
            const refreshError = new Error("refresh failed");
            const refresh = jest.fn().mockRejectedValue(refreshError);
            const { result } = renderHook(() => useInviteAccept({ refresh }));

            let thrownError: unknown;
            await act(async () => {
                try {
                    await result.current.decline(10, 99);
                } catch (e) {
                    thrownError = e;
                }
            });

            expect(mockDelete).toHaveBeenCalledWith("/organizations/10/memberships/99");
            expect(refresh).toHaveBeenCalledTimes(1);
            expect(thrownError).toBeInstanceOf(InviteRefreshError);
            expect(result.current.error).toBeNull();
        });

        test("sets error state and throws standard Error when accept POST fails", async () => {
            const postError = new Error("post failed");
            mockPost.mockRejectedValue(postError);
            const refresh = jest.fn().mockResolvedValue(undefined);
            const { result } = renderHook(() => useInviteAccept({ refresh }));

            let thrownError: unknown;
            await act(async () => {
                try {
                    await result.current.accept(10, 99);
                } catch (e) {
                    thrownError = e;
                }
            });

            expect(mockPost).toHaveBeenCalledWith("/organizations/10/membership_invites/99/accept", undefined);
            expect(refresh).not.toHaveBeenCalled();
            expect(thrownError).toBe(postError);
            expect(thrownError).not.toBeInstanceOf(InviteRefreshError);
            expect(result.current.error).toBe(postError);
        });
    });
});
