// ── Hoisted mocks (must precede import) ──────────────────────────────────────

const mockGet = jest.fn();
const mockPost = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock("../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...args),
        post: (...args: unknown[]) => mockPost(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

import { renderHook, act, waitFor } from "@testing-library/react-native";
import { useOrganizationFollow } from "../src/hooks/useOrganizationFollow";

describe("useOrganizationFollow", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPost.mockReset();
        mockPatch.mockReset();
        mockDelete.mockReset();
    });

    test("follow posts to /organization_follows and sets followId from org GET", async () => {
        mockPost.mockResolvedValueOnce({ redirect: "/public/organizations/1", flash: "Following!" });
        mockGet.mockResolvedValueOnce({ current_user_follow_id: 456, organization: { id: 1 } });

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.follow();
        });

        expect(mockPost).toHaveBeenCalledWith("/organization_follows", { organization_id: 1 });
        expect(mockGet).toHaveBeenCalledWith("/public/organizations/1");
        expect(result.current.followId).toBe(456);
    });

    test("follow rolls back followId on POST failure and rethrows", async () => {
        mockPost.mockRejectedValueOnce(new Error("server 500"));

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await expect(result.current.follow()).rejects.toThrow("server 500");
        });

        expect(result.current.followId).toBeNull(); // restored to prior null
        expect(mockGet).not.toHaveBeenCalled(); // no follow-up GET on POST failure
    });

    test("follow keeps -1 sentinel when org GET fails after successful POST", async () => {
        mockPost.mockResolvedValueOnce({ redirect: "/public/organizations/1" });
        mockGet.mockRejectedValueOnce(new Error("network error"));

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            // @lat: [[mobile-organization-follow-test-notes#useOrganizationFollow.test.tsx]]
            await result.current.follow();
        });

        expect(result.current.followId).toBe(-1); // -1 means "following, id still unknown"
    });

    test("follow rolls back to existing followId on POST failure", async () => {
        mockPost.mockRejectedValueOnce(new Error("network error"));

        const { result } = renderHook(() => useOrganizationFollow(1, 99));
        await act(async () => {
            await expect(result.current.follow()).rejects.toThrow("network error");
        });

        expect(result.current.followId).toBe(99); // restored to prior 99
    });

    test("unfollow deletes /organization_follows/:id and nulls followId", async () => {
        mockDelete.mockResolvedValueOnce(undefined);

        const { result } = renderHook(() => useOrganizationFollow(1, 123));
        await act(async () => {
            await result.current.unfollow();
        });

        expect(mockDelete).toHaveBeenCalledWith("/organization_follows/123");
        expect(result.current.followId).toBeNull();
    });

    test("unfollow rolls back followId on DELETE failure and rethrows", async () => {
        mockDelete.mockRejectedValueOnce(new Error("server error"));

        const { result } = renderHook(() => useOrganizationFollow(1, 123));
        await act(async () => {
            await expect(result.current.unfollow()).rejects.toThrow("server error");
        });

        expect(result.current.followId).toBe(123); // restored
    });

    test("unfollow skips DELETE when followId is null", async () => {
        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.unfollow();
        });

        expect(mockDelete).not.toHaveBeenCalled();
        expect(result.current.followId).toBeNull();
    });

    test("updatePreferences patches /organization_follows/:id/preferences", async () => {
        mockPatch.mockResolvedValueOnce(undefined);

        const { result } = renderHook(() => useOrganizationFollow(1, 123));
        await act(async () => {
            await result.current.updatePreferences({
                notify_on_new_position: true,
                notify_on_support_change: false,
                notify_on_summary_change: true,
                notification_cadence: "daily",
            });
        });

        expect(mockPatch).toHaveBeenCalledWith("/organization_follows/123/preferences", {
            organization_follow: {
                notify_on_new_position: true,
                notify_on_support_change: false,
                notify_on_summary_change: true,
                notification_cadence: "daily",
            },
        });
    });

    test("updatePreferences is a no-op when followId is null", async () => {
        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.updatePreferences({ notify_on_new_position: true });
        });

        expect(mockPatch).not.toHaveBeenCalled();
    });

    test("updatePreferences throws when followId is -1 sentinel (follow in-flight)", async () => {
        // A follow where the POST worked but the GET never came back with the id
        mockPost.mockResolvedValueOnce({ redirect: "/public/organizations/1" });
        mockGet.mockRejectedValueOnce(new Error("GET failed")); // GET fails, so followId lands on -1

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.follow();
        });

        // @lat: [[mobile-organization-follow-test-notes#useOrganizationFollow.test.tsx]]
        await act(async () => {
            await expect(result.current.updatePreferences({ notify_on_new_position: true })).rejects.toThrow(
                "Tracking is not ready yet",
            );
        });

        expect(mockPatch).not.toHaveBeenCalled();
    });

    test("updatePreferences throws on PATCH failure", async () => {
        mockPatch.mockRejectedValueOnce(new Error("save failed"));

        const { result } = renderHook(() => useOrganizationFollow(1, 123));
        await act(async () => {
            await expect(result.current.updatePreferences({ notify_on_new_position: false })).rejects.toThrow(
                "save failed",
            );
        });
    });

    test("hook initializes with provided initialFollowId", async () => {
        const { result } = renderHook(() => useOrganizationFollow(1, 789));
        await waitFor(() => expect(result.current.followId).toBe(789));
    });

    test("unfollow throws for -1 sentinel and does not send DELETE (WR-15)", async () => {
        // Get the hook into the -1 state: the POST works, the GET fails
        mockPost.mockResolvedValueOnce({ redirect: "/public/organizations/1" });
        mockGet.mockRejectedValueOnce(new Error("network error"));

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.follow();
        });
        expect(result.current.followId).toBe(-1); // the placeholder is in place

        await act(async () => {
            await expect(result.current.unfollow()).rejects.toThrow("Tracking is not ready yet");
        });
        expect(mockDelete).not.toHaveBeenCalled();
        // @lat: [[mobile-organization-follow-test-notes#useOrganizationFollow.test.tsx]]
        expect(result.current.followId).toBe(-1);
    });

    test("createFollowWithPrefs posts to /organization_follows with prefs and resolves followId", async () => {
        mockPost.mockResolvedValueOnce({ redirect: "/public/organizations/1" });
        mockGet.mockResolvedValueOnce({ current_user_follow_id: 555 });

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.createFollowWithPrefs({
                notify_on_new_position: true,
                notify_on_support_change: false,
                notify_on_summary_change: true,
                notification_cadence: "daily",
            });
        });

        expect(mockPost).toHaveBeenCalledWith("/organization_follows", {
            organization_id: 1,
            organization_follow: {
                notify_on_new_position: true,
                notify_on_support_change: false,
                notify_on_summary_change: true,
                notification_cadence: "daily",
            },
        });
        expect(mockGet).toHaveBeenCalledWith("/public/organizations/1");
        expect(result.current.followId).toBe(555);
    });

    test("createFollowWithPrefs keeps -1 sentinel when GET fails after POST", async () => {
        mockPost.mockResolvedValueOnce({ redirect: "/public/organizations/1" });
        mockGet.mockRejectedValueOnce(new Error("network error"));

        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.createFollowWithPrefs({ notify_on_new_position: true });
        });

        expect(result.current.followId).toBe(-1);
    });

    test("updatePreferences is still a no-op when followId is null (not following)", async () => {
        const { result } = renderHook(() => useOrganizationFollow(1, null));
        await act(async () => {
            await result.current.updatePreferences({ notify_on_new_position: true });
        });
        expect(mockPatch).not.toHaveBeenCalled();
    });
});
