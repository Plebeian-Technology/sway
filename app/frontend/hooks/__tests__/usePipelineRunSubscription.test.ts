import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";

// Tests for usePipelineRunSubscription: the {connected, downgraded,
// lastDisconnectedAt} return shape with its 2-second sustained-disconnect
// grace timer, payload.scope reload routing, the narrowToBillScope helper,
// and the subscribe / unsubscribe lifecycle.

let connectedCb: () => void;
let disconnectedCb: () => void;
let receivedCb: (payload: unknown) => void;
const subscriptionMock = { unsubscribe: vi.fn<() => void>() };
const routerReload = vi.fn<(...args: unknown[]) => unknown>();

vi.mock("app/frontend/channels/consumer", () => ({
    default: {
        subscriptions: {
            create: vi.fn<(...args: unknown[]) => unknown>((_params: unknown, handlers: unknown) => {
                const h = handlers as {
                    connected: () => void;
                    disconnected: () => void;
                    received: (payload: unknown) => void;
                };
                connectedCb = h.connected;
                disconnectedCb = h.disconnected;
                receivedCb = h.received;
                return subscriptionMock;
            }),
        },
    },
}));

vi.mock("@inertiajs/react", () => ({
    router: { reload: (...args: unknown[]) => routerReload(...args) },
}));

// Imported statically, below the stand-ins that vitest hoists above them.
// @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
import consumer from "app/frontend/channels/consumer";
import {
    BILL_SCOPE_PROPS,
    narrowToBillScope,
    usePipelineRunSubscription,
} from "app/frontend/hooks/usePipelineRunSubscription";
import { PIPELINE_LLM_ONLY_PROPS } from "app/frontend/components/admin/creator/pipelineLlmOnlyProps";

describe("usePipelineRunSubscription — return shape", () => {
    beforeEach(() => {
        vi.useFakeTimers();
    });
    afterEach(() => {
        vi.useRealTimers();
        vi.clearAllMocks();
    });

    it("returns {connected, downgraded, lastDisconnectedAt} shape", () => {
        const { result } = renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        expect(result.current).toHaveProperty("connected");
        expect(result.current).toHaveProperty("downgraded");
        expect(result.current).toHaveProperty("lastDisconnectedAt");
    });

    it("starts {connected: false, downgraded: false, lastDisconnectedAt: null}", () => {
        const { result } = renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        expect(result.current).toEqual({
            connected: false,
            downgraded: false,
            lastDisconnectedAt: null,
        });
    });

    it("flips downgraded=true after 2 seconds sustained disconnect", () => {
        // onlyProps is now a required argument.
        const { result } = renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        act(() => {
            disconnectedCb();
        });
        // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
        expect((result.current as unknown as { downgraded: boolean }).downgraded).toBe(false);
        act(() => {
            vi.advanceTimersByTime(2000);
        });
        expect((result.current as unknown as { downgraded: boolean }).downgraded).toBe(true);
    });

    it("clears the grace timer when reconnect happens within 2s", () => {
        // onlyProps is now a required argument.
        const { result } = renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        act(() => {
            disconnectedCb();
        });
        act(() => {
            vi.advanceTimersByTime(1000);
        });
        act(() => {
            connectedCb();
        });
        act(() => {
            vi.advanceTimersByTime(5000);
        });
        expect((result.current as unknown as { downgraded: boolean }).downgraded).toBe(false);
    });
});

// @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
describe("usePipelineRunSubscription — payload.scope routing", () => {
    beforeEach(() => {
        routerReload.mockClear();
    });

    it("reloads onlyProps on scope='run' payload", () => {
        renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        act(() => {
            receivedCb({ scope: "run", run_id: 1, status: "running" });
        });
        expect(routerReload).toHaveBeenCalledWith({ only: ["legislation_pipeline_run"] });
    });

    it("reloads onlyProps on scope='stage' payload", () => {
        renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        act(() => {
            receivedCb({ scope: "stage", run_id: 1, stage_name: "extract-text" });
        });
        expect(routerReload).toHaveBeenCalledWith({ only: ["legislation_pipeline_run"] });
    });

    it("reloads onlyProps on scope='bill' payload", () => {
        renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        act(() => {
            receivedCb({ scope: "bill", run_id: 1, bill_run_id: 7, status: "succeeded" });
        });
        expect(routerReload).toHaveBeenCalledWith({ only: ["legislation_pipeline_run"] });
    });

    // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
    it("reloads include legislation_pipeline_run on scope='bill' with the production PIPELINE_LLM_ONLY_PROPS tuple", () => {
        renderHook(() => usePipelineRunSubscription("run-1", PIPELINE_LLM_ONLY_PROPS));
        act(() => {
            receivedCb({ scope: "bill", run_id: 1, bill_run_id: 7, status: "succeeded" });
        });
        // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
        const lastCall = routerReload.mock.calls[routerReload.mock.calls.length - 1]?.[0] as {
            only: string[];
        };
        expect(lastCall.only).toContain("legislation_pipeline_run");
    });

    it("reloads onlyProps on a legacy payload (no scope key)", () => {
        renderHook(() => usePipelineRunSubscription("run-1", ["legislation_pipeline_run"]));
        act(() => {
            receivedCb({ event: "webhook" });
        });
        expect(routerReload).toHaveBeenCalledWith({ only: ["legislation_pipeline_run"] });
    });
});

// @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
describe("narrowToBillScope (REVIEW-10 LOW-3)", () => {
    it("keeps every prop in BILL_SCOPE_PROPS", () => {
        const result = narrowToBillScope([
            "bill",
            "pipeline_run_bills",
            "bill_artifact_mirrors",
            "legislation_pipeline_run",
        ]);
        expect(result.sort()).toEqual([...BILL_SCOPE_PROPS].sort());
    });

    it("drops props not in BILL_SCOPE_PROPS (e.g. activity_log_entries)", () => {
        const result = narrowToBillScope(["legislation_pipeline_run", "activity_log_entries", "bill"]);
        expect(result).not.toContain("activity_log_entries");
        expect(result).toContain("legislation_pipeline_run");
        expect(result).toContain("bill");
    });

    it("returns an empty array when no input props match", () => {
        const result = narrowToBillScope(["activity_log_entries", "some_other_prop"]);
        expect(result).toEqual([]);
    });

    it("does not mutate the input array", () => {
        const input = ["bill", "activity_log_entries"];
        const snapshot = [...input];
        narrowToBillScope(input);
        expect(input).toEqual(snapshot);
    });

    it("includes legislation_pipeline_run (cycle-9 HIGH-1 regression guard)", () => {
        // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
        const result = narrowToBillScope(["legislation_pipeline_run", "bill_artifact_mirrors"]);
        expect(result).toContain("legislation_pipeline_run");
    });
});

describe("usePipelineRunSubscription — subscription lifecycle", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("does not subscribe when runId is null", () => {
        renderHook(() => usePipelineRunSubscription(null, ["legislation_pipeline_run"]));
        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        expect(consumer.subscriptions.create).not.toHaveBeenCalled();
    });

    it("subscribes to PipelineRunChannel with the run_id param", () => {
        renderHook(() => usePipelineRunSubscription("abc123", ["legislation_pipeline_run"]));
        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        expect(consumer.subscriptions.create).toHaveBeenCalledWith(
            { channel: "PipelineRunChannel", run_id: "abc123" },
            expect.any(Object),
        );
    });

    it("unsubscribes on unmount", () => {
        const { unmount } = renderHook(() => usePipelineRunSubscription("abc123", ["legislation_pipeline_run"]));
        unmount();
        expect(subscriptionMock.unsubscribe).toHaveBeenCalled();
    });
});
