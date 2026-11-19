// @lat: [[mobile-admin-area#Admin writes]]
let mockIsOnlineState = true;

jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: mockIsOnlineState, lastChecked: new Date() }),
}));

const mockPost = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockPost(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

import { act, renderHook } from "@testing-library/react-native";
import { ApiRequestError } from "../../src/api/errors";
import { useAdminMutation } from "../../src/hooks/admin/useAdminMutation";

describe("useAdminMutation", () => {
    beforeEach(() => {
        mockIsOnlineState = true;
        mockPost.mockReset();
        mockPatch.mockReset();
        mockDelete.mockReset();
    });

    test("starts idle", () => {
        const { result } = renderHook(() => useAdminMutation("patch", "/x"));
        expect(result.current.loading).toBe(false);
        expect(result.current.errorMessage).toBeNull();
        expect(result.current.fieldErrors).toBeNull();
        expect(result.current.errorStatus).toBeNull();
    });

    test("patch sends the body and returns the response", async () => {
        mockPatch.mockResolvedValue({ id: 1 });
        const { result } = renderHook(() => useAdminMutation<{ id: number }>("patch", "/x"));
        let response: { id: number } | null | undefined;
        await act(async () => {
            response = await result.current.run({ name: "a" });
        });
        expect(mockPatch).toHaveBeenCalledWith("/x", { name: "a" });
        expect(response).toEqual({ id: 1 });
        expect(result.current.errorMessage).toBeNull();
    });

    test("post sends the body", async () => {
        mockPost.mockResolvedValue({});
        const { result } = renderHook(() => useAdminMutation("post", "/x"));
        await act(async () => {
            await result.current.run({ a: 1 });
        });
        expect(mockPost).toHaveBeenCalledWith("/x", { a: 1 });
    });

    test("delete sends no body and returns the response", async () => {
        mockDelete.mockResolvedValue({ removed: 2 });
        const { result } = renderHook(() => useAdminMutation<{ removed: number }>("delete", "/x?id=2"));
        let response: { removed: number } | null | undefined;
        await act(async () => {
            response = await result.current.run();
        });
        expect(mockDelete).toHaveBeenCalledWith("/x?id=2");
        expect(response).toEqual({ removed: 2 });
    });

    test("a 204 delete resolves to null", async () => {
        mockDelete.mockResolvedValue(undefined);
        const { result } = renderHook(() => useAdminMutation("delete", "/x"));
        let response: unknown = "unset";
        await act(async () => {
            response = await result.current.run();
        });
        expect(response).toBeNull();
        expect(result.current.errorMessage).toBeNull();
    });

    test("reports loading, then the error message and field errors on a 422", async () => {
        let reject: (e: Error) => void = () => {};
        mockPatch.mockReturnValue(
            new Promise((_resolve, rej) => {
                reject = rej;
            }),
        );
        const { result } = renderHook(() => useAdminMutation("patch", "/x"));
        let pending: Promise<unknown> = Promise.resolve();
        act(() => {
            pending = result.current.run({});
        });
        expect(result.current.loading).toBe(true);
        await act(async () => {
            reject(new ApiRequestError("invalid", "Name is blank", { name: ["is blank"] }, 422));
            await pending;
        });
        expect(result.current.loading).toBe(false);
        expect(result.current.errorMessage).toBe("Name is blank");
        expect(result.current.fieldErrors).toEqual({ name: ["is blank"] });
    });

    test("reports the HTTP status of a failed request until the next run", async () => {
        mockPatch.mockRejectedValueOnce(new ApiRequestError("stale_write", "Moved.", undefined, 409));
        mockPatch.mockResolvedValueOnce({});
        const { result } = renderHook(() => useAdminMutation("patch", "/x"));
        await act(async () => {
            await result.current.run({});
        });
        expect(result.current.errorStatus).toBe(409);
        await act(async () => {
            await result.current.run({});
        });
        expect(result.current.errorStatus).toBeNull();
    });

    test("run resolves to undefined when the request fails", async () => {
        mockPatch.mockRejectedValue(new ApiRequestError("invalid", "Nope", undefined, 422));
        const { result } = renderHook(() => useAdminMutation("patch", "/x"));
        let response: unknown = "unset";
        await act(async () => {
            response = await result.current.run({});
        });
        expect(response).toBeUndefined();
    });

    test("a later success clears the earlier error", async () => {
        mockPatch.mockRejectedValueOnce(new ApiRequestError("invalid", "Nope", { a: ["b"] }, 422));
        mockPatch.mockResolvedValueOnce({});
        const { result } = renderHook(() => useAdminMutation("patch", "/x"));
        await act(async () => {
            await result.current.run({});
        });
        await act(async () => {
            await result.current.run({});
        });
        expect(result.current.errorMessage).toBeNull();
        expect(result.current.fieldErrors).toBeNull();
    });

    test("offline: blocks the request and reports the offline message", async () => {
        mockIsOnlineState = false;
        const { result } = renderHook(() => useAdminMutation("patch", "/x"));
        await act(async () => {
            await result.current.run({});
        });
        expect(mockPatch).not.toHaveBeenCalled();
        expect(result.current.errorMessage).toBe("You need a connection to make this change.");
    });
});
