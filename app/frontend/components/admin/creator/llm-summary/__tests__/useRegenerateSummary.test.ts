// @lat: [[use-regenerate-summary-hook#useRegenerateSummary.test.ts notes]]

import { renderHook, act } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const routerPost = vi.fn<(...args: unknown[]) => void>();
const notify = vi.fn<(options: Record<string, unknown>) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
    },
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: (options: Record<string, unknown>) => notify(options),
}));

import {
    clearRetainedSummaryInstructions,
    getRetainedSummaryInstructions,
    useRegenerateSummary,
} from "../useRegenerateSummary";

beforeEach(() => {
    routerPost.mockReset();
    notify.mockReset();
    clearRetainedSummaryInstructions();
});

describe("useRegenerateSummary — server refusals are visible (C1-CR-01)", () => {
    const postOptions = (): { onError?: (errors: unknown) => void } => {
        const { result } = renderHook(() => useRegenerateSummary(42, "pasted testimony"));
        act(() => result.current.handleRegenerate());

        expect(routerPost).toHaveBeenCalledTimes(1);
        return routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
    };

    it("passes an onError to the regenerate visit", () => {
        expect(typeof postOptions().onError).toBe("function");
    });

    it("toasts the server's generation copy", () => {
        postOptions().onError?.({ generation: "No pipeline data available for regeneration." });

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "No pipeline data available for regeneration.",
        });
    });

    it("falls back to its own copy when the server sends no generation message", () => {
        postOptions().onError?.({});

        expect(notify).toHaveBeenCalledWith({ level: "error", title: expect.stringMatching(/regenerat/i) });
    });

    // @lat: [[use-regenerate-summary-hook#Why onSuccess exists even though onError already covers refusals]]
    it("says so at the control when an expired page stopped the run starting", () => {
        const opts = postOptions() as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };

        opts.onSuccess?.({
            url: "/admin/bill_creator/42/summary",
            props: { flash: { page_expired: true, alert: "The page expired, please try again." } },
        });

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/nothing was queued/i),
        });
        expect(notify).not.toHaveBeenCalledWith(expect.objectContaining({ title: expect.stringMatching(/reload/i) }));
    });

    // @lat: [[use-regenerate-summary-hook#useRegenerateSummary.test.ts notes]]
    it("says nothing at all when the visit was not refused", () => {
        const opts = postOptions() as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };

        opts.onSuccess?.({ url: "/admin/bill_creator/42/summary", props: { flash: {} } });

        expect(notify).not.toHaveBeenCalled();
    });

    // @lat: [[use-regenerate-summary-hook#useRegenerateSummary.test.ts notes]]
    it("says so at the control when the visit landed off the Bill Creator (a lapsed admin session)", () => {
        const opts = postOptions() as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };

        opts.onSuccess?.({ url: "/", props: { flash: {} } });

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/sign in as an admin/i),
        });
    });

    it("clears the loading flag on a refusal, so the CTA is clickable again", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate());

        const opts = routerPost.mock.calls[0][2] as {
            onStart?: () => void;
            onFinish?: () => void;
        };
        act(() => opts.onStart?.());
        expect(result.current.regenLoading).toBe(true);

        act(() => opts.onFinish?.());
        expect(result.current.regenLoading).toBe(false);
    });

    it("passes an onNetworkError callback to the regenerate visit", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate());

        const opts = routerPost.mock.calls[0][2] as { onNetworkError?: () => void };
        expect(typeof opts.onNetworkError).toBe("function");
    });

    it("toasts an error message on network error", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate());

        const opts = routerPost.mock.calls[0][2] as { onNetworkError?: () => void };
        opts.onNetworkError?.();

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/network error/i),
        });
    });

    it("drives onStart, then onNetworkError, and onFinish, invoking onRefused and clearing regenLoading", () => {
        const onRefused = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, onRefused));
        act(() => result.current.handleRegenerate("claude-opus-5-5", "Retained instructions"));

        const opts = routerPost.mock.calls[0][2] as {
            onStart?: () => void;
            onNetworkError?: () => void;
            onFinish?: () => void;
        };

        act(() => opts.onStart?.());
        expect(result.current.regenLoading).toBe(true);

        act(() => opts.onNetworkError?.());
        expect(onRefused).toHaveBeenCalledTimes(1);
        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/network error/i),
        });
        expect(getRetainedSummaryInstructions(42)).toBe("Retained instructions");

        act(() => opts.onFinish?.());
        expect(result.current.regenLoading).toBe(false);
    });
});

describe("useRegenerateSummary — the operator's per-run model choice", () => {
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it("sends the chosen model beside the supplemental testimony", () => {
        const { result } = renderHook(() => useRegenerateSummary(42, "pasted testimony"));
        act(() => result.current.handleRegenerate("claude-opus-5-5"));

        expect(routerPost.mock.calls[0][1]).toEqual({
            supplemental_testimony: "pasted testimony",
            summarization_model: "claude-opus-5-5",
        });
    });

    it("leaves the model out when none was chosen, so the run keeps the standing default", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate());

        expect(routerPost.mock.calls[0][1]).toEqual({});
    });

    // SummaryRunButton types onClick as `() => void`, so tsc does not catch a
    // handler wired straight to onClick receiving the click event.
    it("ignores a click event handed to it in the model position", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => (result.current.handleRegenerate as (arg: unknown) => void)({ type: "click" }));

        expect(routerPost.mock.calls[0][1]).toEqual({});
    });
});

// The caller records "this tab asked for a run" before posting, so a request the
// server refuses has to hand that back — otherwise an unrelated run landing
// later would seed the Public summary box from a draft nobody reviewed.
describe("useRegenerateSummary — a refused request gives the intent back", () => {
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it("calls onRefused when the server returns generation errors", () => {
        const onRefused = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, onRefused));
        act(() => result.current.handleRegenerate());

        const options = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        options.onError?.({ generation: "Generation already in progress" });

        expect(onRefused).toHaveBeenCalledTimes(1);
    });

    it("calls onRefused when the visit landed somewhere other than this bill", () => {
        const onRefused = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, onRefused));
        act(() => result.current.handleRegenerate());

        const options = routerPost.mock.calls[0][2] as { onSuccess?: (page: unknown) => void };
        options.onSuccess?.({ url: "/", props: {} });

        expect(onRefused).toHaveBeenCalledTimes(1);
    });

    it("leaves the intent standing when the run was queued", () => {
        const onRefused = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, onRefused));
        act(() => result.current.handleRegenerate());

        const options = routerPost.mock.calls[0][2] as { onSuccess?: (page: unknown) => void };
        options.onSuccess?.({ url: "/admin/bill_creator/42/summary", props: {} });

        expect(onRefused).not.toHaveBeenCalled();
    });
});

describe("useRegenerateSummary — optional per-run operator instructions", () => {
    it("sends summary_instructions beside the chosen model when provided", () => {
        const { result } = renderHook(() => useRegenerateSummary(42, "pasted testimony"));
        act(() => result.current.handleRegenerate("claude-opus-5-5", "Note the 2.24% property tax rate"));

        expect(routerPost.mock.calls[0][1]).toEqual({
            supplemental_testimony: "pasted testimony",
            summarization_model: "claude-opus-5-5",
            summary_instructions: "Note the 2.24% property tax rate",
        });
    });

    it("trims surrounding ASCII whitespace from summary_instructions but preserves internal newlines and non-ASCII whitespace", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() =>
            result.current.handleRegenerate(
                undefined,
                " \t\r\n\f\vFirst paragraph\n\nSecond\u00A0paragraph with non-breaking space \t\r\n\f\v",
            ),
        );

        expect(routerPost.mock.calls[0][1]).toEqual({
            summary_instructions: "First paragraph\n\nSecond\u00A0paragraph with non-breaking space",
        });
    });

    it("omits summary_instructions when empty or whitespace-only", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate("claude-opus-5-5", "   \t\n  "));

        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "claude-opus-5-5",
        });
    });

    it("omits summary_instructions when undefined", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate("claude-opus-5-5"));

        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "claude-opus-5-5",
        });
    });

    it("ignores click events or non-string values passed in the instructions position", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() =>
            (result.current.handleRegenerate as (model?: string, inst?: unknown) => void)("claude-opus-5-5", {
                type: "click",
                target: {},
            }),
        );

        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "claude-opus-5-5",
        });
    });

    it("invokes onAccepted callback upon successful enqueue", () => {
        const onAccepted = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, undefined, onAccepted));
        act(() => result.current.handleRegenerate(undefined, "Valid instructions"));

        const options = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };
        act(() => options.onSuccess?.({ url: "/admin/bill_creator/42/summary", props: {} }));

        expect(onAccepted).toHaveBeenCalledTimes(1);
    });

    it("does not invoke onAccepted when the page expired", () => {
        const onAccepted = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, undefined, onAccepted));
        act(() => result.current.handleRegenerate(undefined, "Valid instructions"));

        const options = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };
        act(() =>
            options.onSuccess?.({
                url: "/admin/bill_creator/42/summary",
                props: { flash: { page_expired: true } },
            }),
        );

        expect(onAccepted).not.toHaveBeenCalled();
    });

    it("does not invoke onAccepted when landing off the Bill Creator", () => {
        const onAccepted = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, undefined, onAccepted));
        act(() => result.current.handleRegenerate(undefined, "Valid instructions"));

        const options = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };
        act(() =>
            options.onSuccess?.({
                url: "/login",
                props: {},
            }),
        );

        expect(onAccepted).not.toHaveBeenCalled();
    });

    it("does not invoke onAccepted on server refusal onError", () => {
        const onAccepted = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, undefined, onAccepted));
        act(() => result.current.handleRegenerate(undefined, "Valid instructions"));

        const options = routerPost.mock.calls[0][2] as {
            onError?: (errors: unknown) => void;
        };
        act(() => options.onError?.({ generation: "Generation error" }));

        expect(onAccepted).not.toHaveBeenCalled();
    });

    it("does not invoke onAccepted on transport failure onNetworkError", () => {
        const onAccepted = vi.fn<() => void>();
        const { result } = renderHook(() => useRegenerateSummary(42, undefined, undefined, onAccepted));
        act(() => result.current.handleRegenerate(undefined, "Valid instructions"));

        const options = routerPost.mock.calls[0][2] as {
            onNetworkError?: () => void;
        };
        act(() => options.onNetworkError?.());

        expect(onAccepted).not.toHaveBeenCalled();
    });

    it("clears retained instructions when user explicitly erases and submits empty string", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate(undefined, "First run instructions"));
        expect(getRetainedSummaryInstructions(42)).toBe("First run instructions");

        act(() => result.current.handleRegenerate(undefined, ""));
        expect(getRetainedSummaryInstructions(42)).toBe("");
        expect(routerPost.mock.calls[1][1]).not.toHaveProperty("summary_instructions");
    });

    it("clears retained instructions when user submits whitespace-only string", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate(undefined, "First run instructions"));
        expect(getRetainedSummaryInstructions(42)).toBe("First run instructions");

        act(() => result.current.handleRegenerate(undefined, "   \t\n  "));
        expect(getRetainedSummaryInstructions(42)).toBe("");
        expect(routerPost.mock.calls[1][1]).not.toHaveProperty("summary_instructions");
    });

    it("forwards reasoning_effort when provided", () => {
        const { result } = renderHook(() => useRegenerateSummary(42));
        act(() => result.current.handleRegenerate("Gemini Argon Latest", undefined, "high"));
        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/regenerate_summary",
            expect.objectContaining({
                summarization_model: "Gemini Argon Latest",
                reasoning_effort: "high",
            }),
            expect.anything(),
        );
    });
});
