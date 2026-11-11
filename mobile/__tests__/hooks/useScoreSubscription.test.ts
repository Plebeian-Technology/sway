/**
 * useScoreSubscription — listens on ScoreChannel. When the server pushes
 * `refresh_scores`, it calls onRefresh. It unsubscribes when unmounted.
 */

const mockUnsubscribe = jest.fn();
const mockSubscriptionsCreate = jest.fn();

jest.mock("../../src/channels/consumer", () => ({
    getConsumer: jest.fn(async () => ({
        subscriptions: { create: (...args: unknown[]) => mockSubscriptionsCreate(...args) },
    })),
}));

jest.mock("../../src/auth/tokenStore", () => ({
    tokenStore: {
        get: jest.fn(async () => "test-bearer-token"),
    },
}));

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useScoreSubscription } from "../../src/hooks/useScoreSubscription";

interface ChannelHandlers {
    initialize?: () => void;
    received?: (data: { action: string }) => void;
}

describe("useScoreSubscription", () => {
    let capturedHandlers: ChannelHandlers | null = null;

    beforeEach(() => {
        mockUnsubscribe.mockReset();
        mockSubscriptionsCreate.mockReset();
        capturedHandlers = null;
        mockSubscriptionsCreate.mockImplementation((channelName: string, handlers: ChannelHandlers) => {
            // Confirm the channel name matches Rails' app/channels/score_channel.rb.
            expect(channelName).toBe("ScoreChannel");
            capturedHandlers = handlers;
            handlers.initialize?.();
            return { unsubscribe: mockUnsubscribe };
        });
    });

    test("subscribes to ScoreChannel and exposes isSubscribed=true after initialize()", async () => {
        const onRefresh = jest.fn();
        const { result } = renderHook(() => useScoreSubscription(onRefresh));

        await waitFor(() => expect(mockSubscriptionsCreate).toHaveBeenCalled());
        expect(result.current.isSubscribed).toBe(true);
    });

    test("calls onRefresh when received() fires with refresh_scores action", async () => {
        const onRefresh = jest.fn();
        renderHook(() => useScoreSubscription(onRefresh));

        await waitFor(() => expect(capturedHandlers).not.toBeNull());

        await act(async () => {
            capturedHandlers?.received?.({ action: "refresh_scores" });
        });
        expect(onRefresh).toHaveBeenCalledTimes(1);
    });

    test("ignores received() messages with other action values", async () => {
        const onRefresh = jest.fn();
        renderHook(() => useScoreSubscription(onRefresh));

        await waitFor(() => expect(capturedHandlers).not.toBeNull());

        await act(async () => {
            capturedHandlers?.received?.({ action: "other_signal" });
        });
        expect(onRefresh).not.toHaveBeenCalled();
    });

    test("unsubscribes on unmount", async () => {
        const onRefresh = jest.fn();
        const { unmount } = renderHook(() => useScoreSubscription(onRefresh));
        await waitFor(() => expect(mockSubscriptionsCreate).toHaveBeenCalled());

        unmount();
        expect(mockUnsubscribe).toHaveBeenCalledTimes(1);
    });
});
