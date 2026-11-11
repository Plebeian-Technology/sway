import { renderHook, act } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach } from "vitest";
import type { BaseMixin, Subscription } from "@rails/actioncable";

// @lat: [[frontend-test-infrastructure-notes#useScoreSubscription: the test double only implements .unsubscribe()]]
interface MockSubscription extends Record<string, unknown> {
    unsubscribe: () => void;
}

vi.mock("app/frontend/channels/consumer", () => ({
    default: {
        subscriptions: {
            create: vi.fn<(channel: string, handlers: unknown) => MockSubscription>(),
        },
    },
}));

vi.mock("@inertiajs/react", () => ({
    router: { reload: vi.fn<(options?: unknown) => void>() },
}));

const createMockSubscription = (): MockSubscription =>
    ({
        unsubscribe: vi.fn<() => void>(),
    }) as MockSubscription;

import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import consumer from "app/frontend/channels/consumer";
import { router } from "@inertiajs/react";

// oxlint-disable-next-line typescript/unbound-method -- mocks are safe to reference
const getMockCreateSubscription = () => vi.mocked(consumer.subscriptions.create);
// oxlint-disable-next-line typescript/unbound-method -- mocks are safe to reference
const getMockReload = () => vi.mocked(router.reload);

describe("useScoreSubscription", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        // oxlint-disable-next-line typescript/unbound-method -- mocks are safe; vi.mocked() provides proper binding
        vi.mocked(consumer.subscriptions.create).mockReturnValue(
            createMockSubscription() as unknown as Subscription<BaseMixin> & BaseMixin,
        );
    });

    it("creates a ScoreChannel subscription on mount", () => {
        renderHook(() => useScoreSubscription(["bill_score"]));
        expect(getMockCreateSubscription()).toHaveBeenCalledWith(
            "ScoreChannel",
            expect.objectContaining({ received: expect.any(Function) }),
        );
    });

    it("calls router.reload with only props when refresh_scores is received", () => {
        renderHook(() => useScoreSubscription(["bill_score"]));
        const createCall = getMockCreateSubscription().mock.calls[0];
        const handlers = createCall[1] as Record<string, unknown>;
        const receivedCallback = handlers.received as (action: unknown) => void;

        act(() => receivedCallback({ action: "refresh_scores" }));

        // The reload also carries an onFinish, which turns the waiting flag off.
        expect(getMockReload()).toHaveBeenCalledWith(
            expect.objectContaining({ only: ["bill_score"], onFinish: expect.any(Function) }),
        );
    });

    // The waiting flag now tells the truth. It used to be stuck at false,
    // because the `initialize` callback never ran.
    it("returns false initially, true while awaiting a score reload, then false on finish", () => {
        const { result } = renderHook(() => useScoreSubscription(["bill_score"]));
        expect(result.current).toBe(false);

        const handlers = getMockCreateSubscription().mock.calls[0][1] as Record<string, unknown>;
        const receivedCallback = handlers.received as (action: unknown) => void;
        act(() => receivedCallback({ action: "refresh_scores" }));
        expect(result.current).toBe(true);

        const reloadArg = getMockReload().mock.calls[0][0] as Record<string, unknown>;
        const onFinish = reloadArg.onFinish as () => void;
        act(() => onFinish());
        expect(result.current).toBe(false);
    });

    it("ignores non-refresh actions (no reload, flag stays false)", () => {
        const { result } = renderHook(() => useScoreSubscription(["bill_score"]));
        const handlers = getMockCreateSubscription().mock.calls[0][1] as Record<string, unknown>;
        const receivedCallback = handlers.received as (action: unknown) => void;

        act(() => receivedCallback({ action: "something_else" }));

        expect(result.current).toBe(false);
        expect(getMockReload()).not.toHaveBeenCalled();
    });

    it("unsubscribes on unmount", () => {
        const unsubscribe = vi.fn<() => void>();
        getMockCreateSubscription().mockReturnValueOnce({ unsubscribe } as unknown as Subscription<BaseMixin> &
            BaseMixin);

        const { unmount } = renderHook(() => useScoreSubscription(["bill_score"]));
        unmount();

        expect(unsubscribe).toHaveBeenCalled();
    });

    it("does not create a ScoreChannel subscription when enabled is false", () => {
        renderHook(() => useScoreSubscription(["bill_score"], false));
        expect(getMockCreateSubscription()).not.toHaveBeenCalled();
    });
});
