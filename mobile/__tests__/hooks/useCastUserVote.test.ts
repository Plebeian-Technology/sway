let mockIsOnlineState = true;

jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: mockIsOnlineState, lastChecked: new Date() }),
}));

const mockPost = jest.fn(async (_path: string, _body: unknown) => ({}));
jest.mock("../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockPost(...(args as [string, unknown])),
    },
}));

const mockBillClearOne = jest.fn(async (_id: number) => {});
jest.mock("../../src/cache/billCache", () => ({
    clearOne: (...args: unknown[]) => mockBillClearOne(...(args as [number])),
    get: jest.fn(async () => []),
    set: jest.fn(async () => {}),
    clear: jest.fn(async () => {}),
}));

const mockVoteSet = jest.fn(async (_id: number, _vote: unknown) => {});
jest.mock("../../src/cache/voteCache", () => ({
    set: (...args: unknown[]) => mockVoteSet(...(args as [number, unknown])),
    get: jest.fn(async () => null),
}));

const mockLegislatorClear = jest.fn(async () => {});
jest.mock("../../src/cache/legislatorCache", () => ({
    clear: () => mockLegislatorClear(),
    get: jest.fn(async () => []),
    set: jest.fn(async () => {}),
}));

import { renderHook, act } from "@testing-library/react-native";
import { useCastUserVote } from "../../src/hooks/useCastUserVote";

describe("useCastUserVote", () => {
    beforeEach(() => {
        mockIsOnlineState = true;
        mockPost.mockReset();
        mockBillClearOne.mockReset();
        mockVoteSet.mockReset();
        mockLegislatorClear.mockReset();
        mockLegislatorClear.mockResolvedValue(undefined);
        mockPost.mockResolvedValue({});
    });

    test("offline: throws offline_write_blocked sentinel", async () => {
        mockIsOnlineState = false;
        const { result } = renderHook(() => useCastUserVote());
        await expect(result.current.submit(123, "for")).rejects.toThrow("offline_write_blocked");
        expect(mockPost).not.toHaveBeenCalled();
        expect(mockLegislatorClear).not.toHaveBeenCalled();
    });

    test("online: POSTs /user_votes with shaped body and busts caches", async () => {
        const { result } = renderHook(() => useCastUserVote());
        await act(async () => {
            await result.current.submit(42, "against");
        });
        expect(mockPost).toHaveBeenCalledWith("/user_votes", {
            bill_id: 42,
            support: "AGAINST",
        });
        expect(mockVoteSet).toHaveBeenCalledWith(42, expect.objectContaining({ bill_id: 42, support: "against" }));
        expect(mockBillClearOne).toHaveBeenCalledWith(42);
        expect(mockLegislatorClear).toHaveBeenCalled();
    });

    test("propagates errors from apiClient (e.g. 401)", async () => {
        const err = new Error("Unauthorized");
        mockPost.mockRejectedValueOnce(err);
        const { result } = renderHook(() => useCastUserVote());
        await expect(result.current.submit(1, "for")).rejects.toThrow("Unauthorized");
        expect(mockVoteSet).not.toHaveBeenCalled();
        expect(mockBillClearOne).not.toHaveBeenCalled();
        expect(mockLegislatorClear).not.toHaveBeenCalled();
    });

    test("resilient when legislatorCache.clear throws", async () => {
        mockLegislatorClear.mockRejectedValueOnce(new Error("disk error"));
        const { result } = renderHook(() => useCastUserVote());
        await act(async () => {
            await expect(result.current.submit(42, "for")).resolves.toEqual({});
        });
        expect(mockBillClearOne).toHaveBeenCalledWith(42);
        expect(mockLegislatorClear).toHaveBeenCalled();
    });

    test("exposes isOnline from reachability", () => {
        const { result } = renderHook(() => useCastUserVote());
        expect(result.current.isOnline).toBe(true);
    });
});
