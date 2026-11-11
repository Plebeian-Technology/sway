import { Share } from "react-native";
import { renderHook, act } from "@testing-library/react-native";
import { useShareBill } from "../../src/hooks/useShareBill";
import { apiClient } from "../../src/api/client";
import { tokenStore } from "../../src/auth/tokenStore";
import { API_BASE_URL } from "../../src/constants/api";

jest.mock("../../src/api/client", () => ({
    apiClient: {
        post: jest.fn(),
    },
}));

jest.mock("../../src/auth/tokenStore", () => ({
    tokenStore: {
        get: jest.fn(),
    },
}));

describe("useShareBill", () => {
    let shareSpy: jest.SpyInstance;

    beforeEach(() => {
        jest.clearAllMocks();
        shareSpy = jest.spyOn(Share, "share").mockResolvedValue({ action: "sharedAction" });
    });

    afterEach(() => {
        shareSpy.mockRestore();
    });

    test("when authenticated: calls apiClient.post('/user_bill_shares') and invokes Share.share with share_path", async () => {
        (tokenStore.get as jest.Mock).mockResolvedValue("bearer-token-123");
        (apiClient.post as jest.Mock).mockResolvedValue({ share_path: "/bill_shares/uuid-123" });

        const { result } = renderHook(() => useShareBill());
        await act(async () => {
            await result.current.shareBill({ id: 42 });
        });

        expect(apiClient.post).toHaveBeenCalledWith("/user_bill_shares", { bill_id: 42 });
        expect(Share.share).toHaveBeenCalledWith({
            message: `${API_BASE_URL}/bill_shares/uuid-123`,
            url: `${API_BASE_URL}/bill_shares/uuid-123`,
        });
    });

    test("when unauthenticated: skips apiClient.post and invokes Share.share with canonical bill URL", async () => {
        (tokenStore.get as jest.Mock).mockResolvedValue(null);

        const { result } = renderHook(() => useShareBill());
        await act(async () => {
            await result.current.shareBill({ id: 42 });
        });

        expect(apiClient.post).not.toHaveBeenCalled();
        expect(Share.share).toHaveBeenCalledWith({
            message: `${API_BASE_URL}/bills/42`,
            url: `${API_BASE_URL}/bills/42`,
        });
    });

    test("when apiClient.post rejects: falls back to canonical bill URL without throwing", async () => {
        (tokenStore.get as jest.Mock).mockResolvedValue("bearer-token-123");
        (apiClient.post as jest.Mock).mockRejectedValue(new Error("Network request failed"));

        const { result } = renderHook(() => useShareBill());
        await act(async () => {
            await expect(result.current.shareBill({ id: 42 })).resolves.toBeUndefined();
        });

        expect(apiClient.post).toHaveBeenCalledWith("/user_bill_shares", { bill_id: 42 });
        expect(Share.share).toHaveBeenCalledWith({
            message: `${API_BASE_URL}/bills/42`,
            url: `${API_BASE_URL}/bills/42`,
        });
    });

    test("when bill.id is missing: returns early without calling tokenStore, apiClient, or Share.share", async () => {
        (tokenStore.get as jest.Mock).mockResolvedValue("bearer-token-123");

        const { result } = renderHook(() => useShareBill());
        await act(async () => {
            await result.current.shareBill({});
        });

        expect(tokenStore.get).not.toHaveBeenCalled();
        expect(apiClient.post).not.toHaveBeenCalled();
        expect(Share.share).not.toHaveBeenCalled();
    });

    test("when Share.share rejects (e.g. dismissed action): catches gracefully without throwing", async () => {
        (tokenStore.get as jest.Mock).mockResolvedValue(null);
        shareSpy.mockRejectedValue(new Error("User dismissed share dialog"));

        const { result } = renderHook(() => useShareBill());
        await act(async () => {
            await expect(result.current.shareBill({ id: 42 })).resolves.toBeUndefined();
        });

        expect(Share.share).toHaveBeenCalledWith({
            message: `${API_BASE_URL}/bills/42`,
            url: `${API_BASE_URL}/bills/42`,
        });
    });

    test("ignores concurrent shareBill calls while a share operation is already in flight", async () => {
        let resolvePost!: (val: { share_path: string }) => void;
        (tokenStore.get as jest.Mock).mockResolvedValue("bearer-token-123");
        (apiClient.post as jest.Mock).mockReturnValue(
            new Promise((resolve) => {
                resolvePost = resolve;
            }),
        );

        const { result } = renderHook(() => useShareBill());
        await act(async () => {
            const firstCall = result.current.shareBill({ id: 42 });
            const secondCall = result.current.shareBill({ id: 42 });
            resolvePost({ share_path: "/bill_shares/uuid-123" });
            await Promise.all([firstCall, secondCall]);
        });

        expect(apiClient.post).toHaveBeenCalledTimes(1);
        expect(Share.share).toHaveBeenCalledTimes(1);
    });
});
