// @lat: [[bill-creator-initial-values-and-draft-restore#Why the stored draft is scoped to the bill it was taken against]]

import { renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";

// The props usePage() hands back. Each test can change them.
const pagePropsRef: { current: Record<string, unknown> } = { current: {} };
vi.mock("@inertiajs/react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: () => ({ props: pagePropsRef.current }),
    };
});

const localeRef: { current: Record<string, unknown> } = { current: { id: 7, name: "test" } };
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [localeRef.current, vi.fn<() => void>()],
}));

// TempBillStorage.get() pops a toast a moment later; keep it quiet here.
vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return { ...actual, notify: vi.fn<(args: Record<string, unknown>) => void>() };
});

import { useNewBillInitialValues } from "app/frontend/components/admin/creator/hooks/useNewBillInitialValues";

const BILL_KEY = SWAY_STORAGE.Local.BillCreator.Bill;
const CANONICAL_BILL_KEY = BILL_KEY;

const baseProps = (billId: number, title: string) => ({
    bill: { id: billId, external_id: `HB${billId}`, title },
    legislators: [],
    organizations: [],
});

describe("useNewBillInitialValues — bill-scoped draft restore", () => {
    beforeEach(() => {
        localStorage.clear();
        pagePropsRef.current = baseProps(1, "Bill One");
    });

    it("derives initial values from the page bill when no draft is stored", () => {
        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.id).toBe(1);
        expect(result.current.title).toBe("Bill One");
    });

    it("restores a stored draft when it belongs to the current bill", () => {
        localStorage.setItem(BILL_KEY, JSON.stringify({ id: 1, title: "Edited draft for Bill One" }));
        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.title).toBe("Edited draft for Bill One");
    });

    it("ignores a stored draft that belongs to a different bill (the picker bug)", () => {
        // Draft was saved while editing bill 1, but the operator selected bill 2.
        localStorage.setItem(BILL_KEY, JSON.stringify({ id: 1, title: "Edited draft for Bill One" }));
        pagePropsRef.current = baseProps(2, "Bill Two");

        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.id).toBe(2);
        expect(result.current.title).toBe("Bill Two");
    });

    it("restores a new-bill draft (no id) on the new-bill flow", () => {
        localStorage.setItem(BILL_KEY, JSON.stringify({ id: null, title: "Unsaved new bill" }));
        pagePropsRef.current = { bill: { id: null }, legislators: [], organizations: [] };

        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.title).toBe("Unsaved new bill");
    });
});

// bills.summary has two editors: this form and the Summary tab's Save summary
// button. The stored draft carries both the summary the operator was working on
// and the published summary it was written against, so a restore can tell an
// unsaved edit apart from a column somebody else has since moved. (C22-04)
describe("useNewBillInitialValues — a draft must not republish a superseded summary", () => {
    beforeEach(() => {
        localStorage.clear();
    });

    const storeDraft = (draft: Record<string, unknown>) => localStorage.setItem(BILL_KEY, JSON.stringify(draft));

    it("keeps the draft's summary while the server's is the one it was written against", () => {
        pagePropsRef.current = {
            bill: { id: 1, title: "Bill One", summary: "The published summary." },
            legislators: [],
            organizations: [],
        };
        storeDraft({
            id: 1,
            title: "Bill One",
            summary: "A rewrite nobody has saved yet.",
            summary_at_draft_time: "The published summary.",
        });

        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.summary).toBe("A rewrite nobody has saved yet.");
    });

    // @lat: [[bill-creator-initial-values-and-draft-restore#Why the draft's summary yields to a newer published one]]
    it("drops the draft's summary once the server's has moved on", () => {
        pagePropsRef.current = {
            bill: { id: 1, title: "Bill One", summary: "Saved from the Summary tab." },
            legislators: [],
            organizations: [],
        };
        storeDraft({
            id: 1,
            title: "Edited draft for Bill One",
            summary: "The older text this draft was holding.",
            summary_at_draft_time: "The published summary.",
        });

        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.summary).toBe("Saved from the Summary tab.");
        // Only the summary is reconciled. Everything else the operator typed
        // is still their unsaved work and comes back untouched.
        expect(result.current.title).toBe("Edited draft for Bill One");
    });

    // A draft written by an earlier build carries no stamp. It is treated as
    // superseded, which is the safe side to be wrong on.
    it("treats an unstamped draft as superseded", () => {
        pagePropsRef.current = {
            bill: { id: 1, title: "Bill One", summary: "Saved from the Summary tab." },
            legislators: [],
            organizations: [],
        };
        storeDraft({ id: 1, title: "Bill One", summary: "The older text this draft was holding." });

        const { result } = renderHook(() => useNewBillInitialValues());
        expect(result.current.summary).toBe("Saved from the Summary tab.");
    });

    // The stamp is a storage detail. It must not travel into the form, where it
    // would ride along in the submit payload.
    it("does not hand the provenance stamp back to the form", () => {
        pagePropsRef.current = {
            bill: { id: 1, title: "Bill One", summary: "The published summary." },
            legislators: [],
            organizations: [],
        };
        storeDraft({
            id: 1,
            title: "Bill One",
            summary: "The published summary.",
            summary_at_draft_time: "The published summary.",
        });

        const { result } = renderHook(() => useNewBillInitialValues());
        // Round-tripped through JSON, which is what the submit payload does
        // with these values — and which drops a key cleared to undefined.
        expect(JSON.parse(JSON.stringify(result.current))).not.toHaveProperty("summary_at_draft_time");
    });
});

// Dropping the draft's summary is a loss, and the only thing on screen used to
// be the generic "Loaded Data from Temp Storage" toast — the very signal this
// module's own reasoning calls not enough for the loss in the other direction.
// (C23-03)
describe("useNewBillInitialValues — saying so when the unsaved summary is dropped", () => {
    beforeEach(() => {
        localStorage.clear();
        vi.mocked(notify).mockClear();
        vi.useFakeTimers();
        pagePropsRef.current = {
            bill: { id: 1, title: "Bill One", summary: "Saved from the Summary tab." },
            legislators: [],
            organizations: [],
        };
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    // Both toasts are scheduled rather than raised during the render, so the
    // clock has to move before either exists.
    const drainToasts = () => {
        vi.advanceTimersByTime(500);
        return vi.mocked(notify).mock.calls.map(([args]) => (args as Record<string, unknown>).title as string);
    };

    it("tells the operator their unsaved summary was not restored", () => {
        localStorage.setItem(
            BILL_KEY,
            JSON.stringify({
                id: 1,
                title: "Bill One",
                summary: "The paragraph the operator wrote and never saved.",
                summary_at_draft_time: "The published summary.",
            }),
        );

        renderHook(() => useNewBillInitialValues());

        expect(drainToasts()).toContain("Your unsaved summary was not restored");
    });

    it("says nothing when the draft's summary is the one still published", () => {
        localStorage.setItem(
            BILL_KEY,
            JSON.stringify({
                id: 1,
                title: "Bill One",
                summary: "Saved from the Summary tab.",
                summary_at_draft_time: "Saved from the Summary tab.",
            }),
        );

        renderHook(() => useNewBillInitialValues());

        expect(drainToasts()).not.toContain("Your unsaved summary was not restored");
    });

    // @lat: [[temp-bill-storage-peek-parsing#The restore runs once in useNewBillInitialValues]]
    it("says each thing once, even when the page props refresh under the form", () => {
        localStorage.setItem(
            BILL_KEY,
            JSON.stringify({
                id: 1,
                title: "Bill One",
                summary: "The paragraph the operator wrote and never saved.",
                summary_at_draft_time: "The published summary.",
            }),
        );

        const { rerender } = renderHook(() => useNewBillInitialValues());
        vi.advanceTimersByTime(500);

        // What a props refresh looks like: RunConflictBanner's Cancel is a
        // router.delete, preserveState defaults to true for that verb, and
        // @inertiajs/react re-keys the page component only when preserveState
        // is false. So props.bill is a new object and this form is not rebuilt.
        pagePropsRef.current = {
            bill: { id: 1, title: "Bill One", summary: "Saved from the Summary tab." },
            legislators: [],
            organizations: [],
        };
        rerender();
        vi.advanceTimersByTime(500);

        const titles = vi.mocked(notify).mock.calls.map(([args]) => (args as Record<string, unknown>).title as string);
        expect(titles.filter((t) => t === "Your unsaved summary was not restored")).toHaveLength(1);
        expect(titles.filter((t) => t === "Loaded Data from Temp Storage")).toHaveLength(1);
    });

    // @lat: [[temp-bill-storage-peek-parsing#A bad parse returns null on purpose]]
    it.each([
        ["a half-written value", "{oops"],
        ["an empty value", ""],
    ])("keeps the form on screen when the stored draft is %s", (_label, value) => {
        localStorage.setItem(BILL_KEY, value);
        pagePropsRef.current = baseProps(1, "Bill One");

        const { result } = renderHook(() => useNewBillInitialValues());

        expect(result.current.title).toBe("Bill One");
    });

    // A stamp-less draft holding the published text word for word yields, but
    // loses nothing. A toast there would teach the operator to ignore the one
    // that matters.
    it("says nothing when yielding costs the operator nothing", () => {
        localStorage.setItem(
            BILL_KEY,
            JSON.stringify({ id: 1, title: "Bill One", summary: "Saved from the Summary tab." }),
        );

        renderHook(() => useNewBillInitialValues());

        expect(drainToasts()).not.toContain("Your unsaved summary was not restored");
    });
});

// @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
describe("useNewBillInitialValues — which chamber a new bill starts in", () => {
    beforeEach(() => {
        localStorage.clear();
        pagePropsRef.current = { legislators: [], organizations: [] };
    });

    afterEach(() => {
        localeRef.current = { id: 7, name: "test" };
    });

    it("starts a new bill in the chamber the jurisdiction declares", () => {
        localeRef.current = {
            id: 7,
            name: "maryland-maryland-united_states",
            default_bill_chamber: "house",
        };

        const { result } = renderHook(() => useNewBillInitialValues());

        expect(result.current.chamber).toEqual({ label: "house", value: "house" });
    });

    it("starts a Baltimore bill on the council", () => {
        localeRef.current = {
            id: 7,
            name: "baltimore-maryland-united_states",
            default_bill_chamber: "council",
        };

        const { result } = renderHook(() => useNewBillInitialValues());

        expect(result.current.chamber).toEqual({ label: "council", value: "council" });
    });

    // No guess for a jurisdiction nobody has declared. useBillFormSubmit's
    // required-field check then asks the admin to pick one.
    it("picks nothing when the jurisdiction declares no chamber", () => {
        localeRef.current = { id: 7, name: "austin-texas-united_states", default_bill_chamber: null };

        const { result } = renderHook(() => useNewBillInitialValues());

        expect(result.current.chamber).toBeNull();
    });

    describe("useNewBillInitialValues — evidence fields in a restored draft", () => {
        beforeEach(() => {
            localStorage.clear();
            pagePropsRef.current = baseProps(1, "Bill One");
        });

        it("preserves news_usage and source_uses through draft restore", () => {
            const evidencePayload = {
                id: 1,
                title: "Bill One",
                news_usage: "cited" as const,
                source_uses: [
                    {
                        bill_news_article_id: 77,
                        claim_text: "Evidence claim",
                        evidence_excerpt: "Evidence excerpt",
                        citation_url: "https://example.com/news",
                    },
                ],
            };
            localStorage.setItem(CANONICAL_BILL_KEY, JSON.stringify(evidencePayload));

            const { result } = renderHook(() => useNewBillInitialValues());
            expect(result.current.news_usage).toBe("cited");
            expect(result.current.source_uses).toEqual(evidencePayload.source_uses);
        });
    });
});
