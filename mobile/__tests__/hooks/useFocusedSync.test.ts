const mockUnsubscribeChannel = jest.fn();
const mockSubscriptionsCreate = jest.fn();
const mockNetInfoUnsubscribe = jest.fn();
const mockNetInfoAddListener = jest.fn();

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

jest.mock("@react-native-community/netinfo", () => ({
    __esModule: true,
    addEventListener: (...args: unknown[]) => mockNetInfoAddListener(...args),
}));

// Fake useFocusEffect so the callback runs right away on mount and its cleanup
// runs right away on unmount. That matches what React Navigation does for a
// screen sitting under the tab the user is currently on.
jest.mock("@react-navigation/native", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        useFocusEffect: (cb: () => undefined | (() => void)) => {
            ReactMod.useEffect(() => cb(), [cb]);
        },
    };
});

import { renderHook, waitFor, act } from "@testing-library/react-native";
import { useFocusedSync } from "../../src/hooks/useFocusedSync";

interface ChannelHandlers {
    received?: (data: { action: string }) => void;
}

describe("useFocusedSync", () => {
    beforeEach(() => {
        mockUnsubscribeChannel.mockReset();
        mockSubscriptionsCreate.mockReset();
        mockNetInfoUnsubscribe.mockReset();
        mockNetInfoAddListener.mockReset();

        mockSubscriptionsCreate.mockImplementation((_name: string, _handlers: ChannelHandlers) => ({
            unsubscribe: mockUnsubscribeChannel,
        }));

        mockNetInfoAddListener.mockImplementation(() => mockNetInfoUnsubscribe);

        jest.useFakeTimers();
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    test("starts polling at the supplied interval while focused", async () => {
        const refresh = jest.fn();
        renderHook(() => useFocusedSync({ refresh, pollMs: 5000 }));

        await act(async () => {
            jest.advanceTimersByTime(5000);
        });
        expect(refresh).toHaveBeenCalledTimes(1);
        await act(async () => {
            jest.advanceTimersByTime(5000);
        });
        expect(refresh).toHaveBeenCalledTimes(2);
    });

    test("subscribes to ScoreChannel and triggers refresh on refresh_scores push", async () => {
        let captured: ChannelHandlers | null = null;
        mockSubscriptionsCreate.mockImplementation((_name: string, handlers: ChannelHandlers) => {
            captured = handlers;
            return { unsubscribe: mockUnsubscribeChannel };
        });

        const refresh = jest.fn();
        renderHook(() => useFocusedSync({ refresh, pollMs: 60000 }));

        await waitFor(() => expect(captured).not.toBeNull());
        await act(async () => {
            captured?.received?.({ action: "refresh_scores" });
        });
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("registers a NetInfo listener and fires refresh on offline → online transition", async () => {
        let netListener: ((s: { isConnected: boolean }) => void) | null = null;
        mockNetInfoAddListener.mockImplementation((cb: (s: { isConnected: boolean }) => void) => {
            netListener = cb;
            return mockNetInfoUnsubscribe;
        });

        const refresh = jest.fn();
        renderHook(() => useFocusedSync({ refresh, pollMs: 60000 }));

        await waitFor(() => expect(mockNetInfoAddListener).toHaveBeenCalled());

        // The first event reports isConnected=true. That is the starting state
        // rather than a change, so nothing refreshes.
        await act(async () => {
            netListener?.({ isConnected: true });
        });
        expect(refresh).not.toHaveBeenCalled();

        await act(async () => {
            netListener?.({ isConnected: false });
        });
        expect(refresh).not.toHaveBeenCalled();

        // Come back online — this is the change that matters.
        await act(async () => {
            netListener?.({ isConnected: true });
        });
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("cleanup tears down interval + channel subscription + NetInfo listener", async () => {
        const refresh = jest.fn();
        const { unmount } = renderHook(() => useFocusedSync({ refresh, pollMs: 1000 }));

        await waitFor(() => expect(mockSubscriptionsCreate).toHaveBeenCalled());
        await waitFor(() => expect(mockNetInfoAddListener).toHaveBeenCalled());

        unmount();

        expect(mockUnsubscribeChannel).toHaveBeenCalledTimes(1);
        expect(mockNetInfoUnsubscribe).toHaveBeenCalledTimes(1);

        refresh.mockReset();
        await act(async () => {
            jest.advanceTimersByTime(10_000);
        });
        expect(refresh).not.toHaveBeenCalled();
    });
});
