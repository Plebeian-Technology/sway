// Tested standalone because the edge cases — missing key, blank message, non-string value — are
// hard to trigger through a full component.

import { beforeEach, describe, expect, it, vi } from "vitest";

const notify = vi.fn<(...args: unknown[]) => void>();

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notify(...args),
}));

import { isPrivateIndividualRefusal, notifyServerRefusal, serverRefusalMessage } from "../notifyServerRefusal";

beforeEach(() => {
    notify.mockClear();
});

describe("serverRefusalMessage", () => {
    it("returns the server copy for the requested key", () => {
        expect(serverRefusalMessage({ org_position: "This draft list has changed" }, "org_position")).toBe(
            "This draft list has changed",
        );
    });

    it("ignores a message filed under a different key", () => {
        expect(serverRefusalMessage({ generation: "No pipeline data available" }, "org_position")).toBeUndefined();
    });

    it("treats a blank message as absent so the caller's fallback is used", () => {
        expect(serverRefusalMessage({ generation: "   " }, "generation")).toBeUndefined();
    });

    it("survives the shapes Inertia can hand an onError callback", () => {
        expect(serverRefusalMessage({}, "generation")).toBeUndefined();
        expect(serverRefusalMessage(undefined, "generation")).toBeUndefined();
        expect(serverRefusalMessage(null, "generation")).toBeUndefined();
        expect(serverRefusalMessage({ generation: { nested: "shape" } }, "generation")).toBeUndefined();
    });
});

describe("notifyServerRefusal", () => {
    it("toasts the server copy at error level", () => {
        notifyServerRefusal({ org_position: "The testimony behind this draft was retracted" }, "org_position", "nope");

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "The testimony behind this draft was retracted",
        });
    });

    it("falls back to the caller's copy when the server sent nothing usable", () => {
        notifyServerRefusal({}, "generation", "Could not start generation.");

        expect(notify).toHaveBeenCalledWith({ level: "error", title: "Could not start generation." });
    });

    // @lat: [[toasts#Toasts#Flash toast dedupe#A refusal that arrives in the errors hash needs its own reader]]
    it("reads the legislator_votes channel LegislatorVotesController refuses on", () => {
        expect(
            serverRefusalMessage(
                { legislator_votes: "Failed to save votes for legislator(s): 7." },
                "legislator_votes",
            ),
        ).toBe("Failed to save votes for legislator(s): 7.");

        notifyServerRefusal({}, "legislator_votes", "Could not save legislator votes.");
        expect(notify).toHaveBeenCalledWith({ level: "error", title: "Could not save legislator votes." });
    });

    it("reads the pipeline channel force_fail and enqueue_pipeline_run! refuse on", () => {
        expect(serverRefusalMessage({ pipeline: "Confirmation phrase mismatch" }, "pipeline")).toBe(
            "Confirmation phrase mismatch",
        );

        notifyServerRefusal({}, "pipeline", "Could not force-fail this run.");
        expect(notify).toHaveBeenCalledWith({ level: "error", title: "Could not force-fail this run." });
    });
});

// @lat: [[private-individual-guard-override]]
describe("isPrivateIndividualRefusal", () => {
    it("is true when the server flags the refusal", () => {
        expect(isPrivateIndividualRefusal({ org_position: "...", private_individual_refusal: true })).toBe(true);
    });

    it("is false for an ordinary org_position refusal with no flag", () => {
        expect(isPrivateIndividualRefusal({ org_position: "This draft list has changed" })).toBe(false);
    });

    it("survives the shapes Inertia can hand an onError callback", () => {
        expect(isPrivateIndividualRefusal({})).toBe(false);
        expect(isPrivateIndividualRefusal(undefined)).toBe(false);
        expect(isPrivateIndividualRefusal(null)).toBe(false);
        expect(isPrivateIndividualRefusal({ private_individual_refusal: "true" })).toBe(false);
    });
});
