// @lat: [[bill-category-redirect-prop-freshness#Test setup notes for BillCreatorSummaryAndPositions.test.tsx]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

// ── Stand-ins for the child sections ─────────────────────────────────────────
vi.mock("app/frontend/components/admin/creator/BillCreatorLlmSummary", () => ({
    __esModule: true,
    default: () => <div data-testid="section-BillCreatorLlmSummary">BillCreatorLlmSummary</div>,
}));

// ── Fake shared UI pieces for the category override ──────────────────────────
// @lat: [[bill-category-redirect-prop-freshness#Test setup notes for BillCreatorSummaryAndPositions.test.tsx]]
vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({
        children,
        variant: _variant,
        tone: _tone,
        ...rest
    }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string; tone?: string }) => (
        <span data-slot="badge" {...rest}>
            {children}
        </span>
    ),
}));

// @lat: [[bill-category-redirect-prop-freshness#Test setup notes for BillCreatorSummaryAndPositions.test.tsx]]
vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({ children, onValueChange }: { children: React.ReactNode; onValueChange?: (v: string) => void }) => {
        let ariaLabel: string | undefined;
        React.Children.forEach(children, (child) => {
            if (React.isValidElement(child)) {
                const label = (child.props as { "aria-label"?: string })["aria-label"];
                if (label) ariaLabel = label;
            }
        });
        return (
            <select
                data-testid="select-add-category"
                aria-label={ariaLabel}
                onChange={(e) => onValueChange?.(e.target.value)}
            >
                {children}
            </select>
        );
    },
    SelectTrigger: ({ children }: { children: React.ReactNode; "aria-label"?: string }) => <>{children}</>,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
        <option value={value}>{children}</option>
    ),
}));

// ── Fake hooks and a fake Inertia router ─────────────────────────────────────
const usePageMock = vi.fn<() => Record<string, unknown>>();

// A successful, non-page-expired visit. BillCategoryOverride's onSuccess reads
// page.props.flash via pageExpired() first, so the fake page must look real, not undefined.
const fakeSuccessPage = { props: {} };

// Router calls the category override tests can watch. post and delete run their
// onSuccess callback right away, so the router.reload checks work without any
// async setup.
const routerPost = vi
    .fn<
        (
            _url: string,
            _data: unknown,
            opts?: { onSuccess?: (page: typeof fakeSuccessPage) => void; onError?: (errors: unknown) => void },
        ) => void
    >()
    .mockImplementation(
        (
            _url: string,
            _data: unknown,
            opts?: { onSuccess?: (page: typeof fakeSuccessPage) => void; onError?: (errors: unknown) => void },
        ) => opts?.onSuccess?.(fakeSuccessPage),
    );
const routerDelete = vi
    .fn<(_url: string, opts?: { onSuccess?: (page: typeof fakeSuccessPage) => void }) => void>()
    .mockImplementation((_url: string, opts?: { onSuccess?: (page: typeof fakeSuccessPage) => void }) =>
        opts?.onSuccess?.(fakeSuccessPage),
    );
const routerReload = vi.fn<(opts?: Record<string, unknown>) => void>();

// @lat: [[bill-creator-summary-tab#Why the poller is a mounted component]]
const usePollMock = vi.fn<(...args: unknown[]) => void>();
const pollDestroySpy = vi.fn<() => void>();
vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    usePoll: function usePoll(...args: unknown[]) {
        usePollMock(...args);
        // Copy usePoll's behavior: one effect when the component appears, plus
        // a cleanup when it goes away. The empty dependency list means the
        // effect is set up once and the cleanup runs on removal.
        React.useEffect(() => () => pollDestroySpy(), []);
    },
    // A router the tests can watch, for the category override checks.
    router: {
        post: (...args: unknown[]) => (routerPost as (...a: unknown[]) => void)(...args),
        delete: (...args: unknown[]) => (routerDelete as (...a: unknown[]) => void)(...args),
        reload: (...args: unknown[]) => (routerReload as (...a: unknown[]) => void)(...args),
    },
}));
vi.mock("app/frontend/hooks/usePipelineRunSubscription", () => ({
    usePipelineRunSubscription: () => ({ connected: true, downgraded: false, lastDisconnectedAt: null }),
}));

// Import only AFTER the fakes above are in place.
import BillCreatorSummary, { SUMMARY_ONLY_PROPS } from "app/frontend/components/admin/creator/BillCreatorSummary";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    usePollMock.mockReset();
    pollDestroySpy.mockReset();
    routerPost.mockClear();
    routerDelete.mockClear();
    routerReload.mockClear();
});

describe("BillCreatorSummary", () => {
    it("renders LlmSummary + CategoryOverride in order when a bill is selected with provisioning", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { llm_generated_at: "2026-05-18T12:00:00Z" } },
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        const sections = Array.from(document.querySelectorAll("[data-testid^='section-']")).map(
            (el) => el.getAttribute("data-testid")!,
        );
        expect(sections).toEqual([
            "section-BillCreatorLlmSummary",
            "section-BillCreatorNewsArticles",
            "section-BillCategoryOverride",
        ]);

        // @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
        expect(screen.queryByText("Supporting / opposing arguments")).toBeNull();
        expect(screen.queryByTestId("section-BillCreatorOrganizations")).toBeNull();
    });

    it("renders the no-bill-selected empty state when bill.id is falsy", () => {
        usePageMock.mockReturnValue({
            props: { bill: undefined, active_legislation_pipeline_run: null },
        });
        render(<BillCreatorSummary />);

        expect(screen.getByTestId("summary-no-bill-selected")).toBeTruthy();
        expect(screen.queryByTestId("section-BillCreatorLlmSummary")).toBeNull();
        expect(screen.queryByTestId("section-BillCategoryOverride")).toBeNull();
    });

    it("renders the no-bill-selected empty state when bill.id is 0 or negative", () => {
        usePageMock.mockReturnValue({
            props: { bill: { id: 0 }, active_legislation_pipeline_run: null },
        });
        render(<BillCreatorSummary />);

        expect(screen.getByTestId("summary-no-bill-selected")).toBeTruthy();
    });

    it("does NOT render the category override section when provisioning is absent", () => {
        usePageMock.mockReturnValue({
            props: {
                // A bill is selected, but it has no bill_llm_provisioning record.
                bill: { id: 42, bill_llm_provisioning: null },
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        expect(screen.queryByTestId("section-BillCategoryOverride")).toBeNull();
        expect(screen.getByTestId("section-BillCreatorLlmSummary")).toBeTruthy();
    });

    // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props#Why the summary tab polls at all]]
    it.each(["pending", "generating"])(
        "mounts the poller (calls usePoll once) while generation_status is %s",
        (status) => {
            usePageMock.mockReturnValue({
                props: {
                    bill: { id: 42, bill_llm_provisioning: { generation_status: status } },
                    active_legislation_pipeline_run: null,
                },
            });
            render(<BillCreatorSummary />);

            expect(usePollMock).toHaveBeenCalledTimes(1);
            expect(usePollMock).toHaveBeenCalledWith(5000, { only: [...SUMMARY_ONLY_PROPS] });
        },
    );

    it.each(["completed", "failed", "skipped", undefined, null])(
        "does NOT mount the poller (usePoll never called) when generation_status is %s",
        (status) => {
            usePageMock.mockReturnValue({
                props: {
                    bill: { id: 42, bill_llm_provisioning: { generation_status: status } },
                    active_legislation_pipeline_run: null,
                },
            });
            render(<BillCreatorSummary />);

            expect(usePollMock).not.toHaveBeenCalled();
        },
    );

    // @lat: [[summary-tab-pipeline-running-poll-fallback#BillCreatorSummaryAndPositions.test.tsx pins the completed+running pairing]]
    it("mounts the poller while this bill's pipeline is busy, even with a finished summary", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { generation_status: "completed" },
                    bill_pipeline_refresh: { status: "fetching_hearings" },
                },
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(5000, { only: [...SUMMARY_ONLY_PROPS] });
    });

    // The other half of the rule: the timer runs only as long as there's a notice on
    // screen, so the reload that clears the notice is also what ends the polling.
    it("stops the poller once this bill's pipeline run finishes", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { generation_status: "completed" },
                    bill_pipeline_refresh: { status: "running" },
                },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorSummary />);
        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(pollDestroySpy).not.toHaveBeenCalled();

        usePollMock.mockClear();
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { generation_status: "completed" },
                    bill_pipeline_refresh: null,
                },
                active_legislation_pipeline_run: null,
            },
        });
        rerender(<BillCreatorSummary />);

        expect(usePollMock).not.toHaveBeenCalled();
        expect(pollDestroySpy).toHaveBeenCalledTimes(1);
    });

    it("unmounts the poller and fires usePoll's destroy cleanup when generation_status transitions in-flight → settled", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { generation_status: "generating" } },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorSummary />);
        expect(usePollMock).toHaveBeenCalledTimes(1);
        // Check first: no cleanup yet, because the poller is still on the page.
        expect(pollDestroySpy).not.toHaveBeenCalled();

        // The server sends the finished status through a partial reload; the poller leaves
        // once isGenerating === false, and usePoll's cleanup runs — nothing calls usePoll again.
        usePollMock.mockClear();
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { generation_status: "completed" } },
                active_legislation_pipeline_run: null,
            },
        });
        rerender(<BillCreatorSummary />);

        // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props#Why the summary tab polls at all]]
        expect(usePollMock).not.toHaveBeenCalled();
        expect(pollDestroySpy).toHaveBeenCalledTimes(1);
    });

    // LlmSummaryEmptyState's stale guard can't learn billPipelineStatus moved without a provisioning row —
    // the subscription only follows a run active at mount.
    it("mounts the poller while there is no provisioning row, so the empty-state prompt guard sees fresh status", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: null },
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(5000, { only: [...SUMMARY_ONLY_PROPS] });
    });

    it("stops the poller once a provisioning row with a settled status arrives", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: null },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorSummary />);
        expect(usePollMock).toHaveBeenCalledTimes(1);

        usePollMock.mockClear();
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { generation_status: "completed" } },
                active_legislation_pipeline_run: null,
            },
        });
        rerender(<BillCreatorSummary />);

        expect(usePollMock).not.toHaveBeenCalled();
        expect(pollDestroySpy).toHaveBeenCalledTimes(1);
    });

    // @lat: [[bill-creator-positions-tab#Splitting the tab split the poll list]]
    it("exports SUMMARY_ONLY_PROPS with the props the tab actually consumes", () => {
        expect([...SUMMARY_ONLY_PROPS]).toEqual(["bill", "active_legislation_pipeline_run", "summary_sources"]);
    });

    it("asks for no prop only the positions tab reads", () => {
        for (const positionsProp of [
            "organizations",
            "testimony_coverage",
            "testimony_campaign_drafts",
            "testimony_claimed_affiliations",
            "campaigns",
        ]) {
            expect([...SUMMARY_ONLY_PROPS]).not.toContain(positionsProp);
        }
    });
});

// ── Category override integration tests ──────────────────────────────────────
// @lat: [[bill-category-redirect-prop-freshness#Test setup notes for BillCreatorSummaryAndPositions.test.tsx]]
describe("BillCreatorSummary — BillCategoryOverride integration", () => {
    const billWithProvisioning = {
        id: 42,
        bill_llm_provisioning: { llm_generated_at: "2026-06-01T12:00:00Z" },
        override_categories: [
            { id: 1, name: "Housing", active: true },
            { id: 2, name: "Health", active: true },
        ],
    };
    const activeCategories = [
        { id: 1, name: "Housing" },
        { id: 2, name: "Health" },
        { id: 3, name: "Economy" },
    ];

    it("clicking × on a category badge asks the server to remove it, and asks once", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: billWithProvisioning,
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        // Click the × remove button for "Housing" (id: 1)
        fireEvent.click(screen.getByLabelText("Remove Housing"));

        expect(routerDelete).toHaveBeenCalledWith(
            "/bills/42/categories/1",
            expect.objectContaining({ onSuccess: expect.any(Function) }),
        );
        // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props#A redirect already refreshes the page]]
        expect(routerReload).not.toHaveBeenCalled();
    });

    it("selecting a category from the Select asks the server to add it, and asks once", () => {
        // Only 2 categories assigned; Economy (id: 3) is available in the dropdown.
        usePageMock.mockReturnValue({
            props: {
                bill: billWithProvisioning,
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        const addSelect = screen.getByTestId("select-add-category");
        fireEvent.change(addSelect, { target: { value: "3" } });

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/categories",
            { category_id: 3 },
            expect.objectContaining({ onSuccess: expect.any(Function) }),
        );
        // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props#A redirect already refreshes the page]]
        expect(routerReload).not.toHaveBeenCalled();
    });

    it("remounts and resets the Select component when adding a category fails (D-I-01)", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: billWithProvisioning,
                active_categories: activeCategories,
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        const selectBefore = screen.getByTestId("select-add-category");

        routerPost.mockImplementationOnce((_url, _data, opts) => {
            opts?.onError?.({ message: "Could not add category." });
        });

        fireEvent.change(selectBefore, { target: { value: "3" } });

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/categories",
            { category_id: 3 },
            expect.objectContaining({ onError: expect.any(Function) }),
        );

        const selectAfter = screen.getByTestId("select-add-category");
        expect(selectAfter).not.toBe(selectBefore);
    });

    it("exposes the 'Add category' accessible name on the combobox trigger (W-07)", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: billWithProvisioning,
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        // Radix puts aria-label on the trigger button (the combobox), not the root element that only
        // carries shared state — that's what makes it findable by accessible name.
        expect(screen.getByRole("combobox", { name: /add category/i })).toBeTruthy();
    });

    it("hides the Select and shows 'Maximum 3 categories assigned.' when bill has 3 categories (T-60-18)", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { llm_generated_at: "2026-06-01T12:00:00Z" },
                    override_categories: [
                        { id: 1, name: "Housing", active: true },
                        { id: 2, name: "Health", active: true },
                        { id: 3, name: "Economy", active: true },
                    ],
                },
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        // The dropdown disappears once the limit is reached
        expect(screen.queryByTestId("select-add-category")).toBeNull();
        // and the "at the limit" message appears
        expect(screen.getByText("Maximum 3 categories assigned.")).toBeTruthy();
    });

    it("V-A-W-01: an inactive leftover does not count toward the cap (2 active + 1 inactive is not at max)", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { llm_generated_at: "2026-06-01T12:00:00Z" },
                    override_categories: [
                        { id: 1, name: "Housing", active: true },
                        { id: 2, name: "Health", active: true },
                        { id: 9, name: "Deprecated", active: false },
                    ],
                },
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        // Three rows, only two active, so the limit isn't reached — the dropdown still shows and "Maximum 3"
        // must not appear. The inactive chip is an old leftover.
        expect(screen.queryByText("Maximum 3 categories assigned.")).toBeNull();
        expect(screen.queryByTestId("select-add-category")).not.toBeNull();
    });

    it("shows 'No categories assigned yet. Add one below.' when bill has no categories (empty state)", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { llm_generated_at: "2026-06-01T12:00:00Z" },
                    override_categories: [],
                },
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        expect(screen.getByText("No categories assigned yet. Add one below.")).toBeTruthy();
    });

    it("heading 'Categories' renders in the override section", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: billWithProvisioning,
                active_categories: activeCategories,
                // The server sends the limit (Category::MAX_ACTIVE_PER_BILL);
                // the component does not keep its own copy of the number.
                max_active_categories_per_bill: 3,
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorSummary />);

        expect(screen.getByText("Categories")).toBeTruthy();
    });
});

describe("BillCreatorSummary — the no-provisioning poll is bounded", () => {
    const ONE_MINUTE_MS = 12 * 5000;

    afterEach(() => {
        vi.useRealTimers();
    });

    // @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
    it("stops polling a bill with no provisioning row once the watch runs out", () => {
        vi.useFakeTimers();
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: null },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorSummary />);
        expect(usePollMock).toHaveBeenCalledTimes(1);

        usePollMock.mockClear();
        React.act(() => {
            vi.advanceTimersByTime(ONE_MINUTE_MS);
        });
        rerender(<BillCreatorSummary />);

        expect(usePollMock).not.toHaveBeenCalled();
        expect(pollDestroySpy).toHaveBeenCalledTimes(1);
    });

    it("keeps polling past the bound while this bill's pipeline is busy", () => {
        vi.useFakeTimers();
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: null, bill_pipeline_refresh: { status: "running" } },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorSummary />);
        expect(usePollMock).toHaveBeenCalledTimes(1);

        usePollMock.mockClear();
        React.act(() => {
            vi.advanceTimersByTime(ONE_MINUTE_MS * 3);
        });
        rerender(<BillCreatorSummary />);

        expect(usePollMock).toHaveBeenCalled();
        expect(pollDestroySpy).not.toHaveBeenCalled();
    });

    it("gives a fresh watch to the next bill the operator picks", () => {
        vi.useFakeTimers();
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: null },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorSummary />);

        React.act(() => {
            vi.advanceTimersByTime(ONE_MINUTE_MS);
        });
        rerender(<BillCreatorSummary />);
        usePollMock.mockClear();

        usePageMock.mockReturnValue({
            props: {
                bill: { id: 43, bill_llm_provisioning: null },
                active_legislation_pipeline_run: null,
            },
        });
        rerender(<BillCreatorSummary />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
    });
});

// @lat: [[bill-creator-summary-tab#Where the summary stops and the positions start]]
describe("the tab's section headings", () => {
    const renderWithProvisioning = () => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { llm_generated_at: "2026-05-18T12:00:00Z" } },
                active_legislation_pipeline_run: null,
            },
        });
        return render(<BillCreatorSummary />);
    };

    it.each(["Categories", "News articles"])("opens %s at level 3", (name) => {
        renderWithProvisioning();

        expect(screen.getByRole("heading", { name, level: 3 })).toBeTruthy();
    });

    it("carries no ALL-CAPS heading — caps survive on status badges alone", () => {
        renderWithProvisioning();

        for (const heading of screen.getAllByRole("heading")) {
            expect(heading.className).not.toContain("uppercase");
        }
    });
});
