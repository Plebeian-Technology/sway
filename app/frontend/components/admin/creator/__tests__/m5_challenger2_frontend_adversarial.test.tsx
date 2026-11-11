import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ConfirmOptions } from "app/frontend/components/ui/confirm-dialog";

const routerPost = vi.fn<(...args: unknown[]) => void>();
const routerPatch = vi.fn<(...args: unknown[]) => void>();
const routerReload = vi.fn<(...args: unknown[]) => void>();
const usePageMock = vi.fn<() => Record<string, unknown>>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        patch: (...args: unknown[]) => routerPatch(...args),
        reload: (...args: unknown[]) => routerReload(...args),
    },
}));

const notifyMock = vi.fn<(options: Record<string, unknown>) => void>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (options: Record<string, unknown>) => notifyMock(options),
}));

const confirmMock = vi.fn<(options: ConfirmOptions) => Promise<boolean>>();
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({
        children,
        tone,
        ...props
    }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string; tone?: string }) => (
        <span data-tone={tone} {...props}>
            {children}
        </span>
    ),
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, disabled, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} disabled={disabled} {...props}>
            {children}
        </button>
    ),
}));

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
}));

vi.mock("app/frontend/components/ui/input", () => ({
    Input: (props: React.InputHTMLAttributes<HTMLInputElement>) => <input {...props} />,
}));

vi.mock("app/frontend/components/ui/label", () => ({
    Label: ({ children, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) => (
        <label {...props}>{children}</label>
    ),
}));

vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({
        children,
        value,
        onValueChange,
    }: {
        children: React.ReactNode;
        value: string;
        onValueChange: (v: string) => void;
    }) => (
        <select data-testid="select-edit-stance" value={value} onChange={(e) => onValueChange(e.target.value)}>
            {children}
        </select>
    ),
    SelectTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
        <option value={value}>{children}</option>
    ),
}));

import BillCreatorOrgPositionCard from "app/frontend/components/admin/creator/BillCreatorOrgPositionCard";
import LlmSummaryOrgPositions from "app/frontend/components/admin/creator/llm-summary/LlmSummaryOrgPositions";
import BillCreatorTestimonyPositions from "app/frontend/components/admin/creator/BillCreatorTestimonyPositions";
import {
    IBillLlmProvisioning,
    IOrgPosition,
    TDraftOrgPosition,
} from "app/frontend/components/admin/creator/llm-summary/types";

const NO_TESTIMONY_NOTICE_ID = "llm-no-testimony-notice";
const RUN_IN_FLIGHT_NOTICE_ID = "llm-run-in-flight-notice";
const TESTIMONY_COVERAGE_NOTICE_ID = "llm-testimony-coverage-notice";

const sampleNewsPosition: IOrgPosition = {
    org_name: "Harbor Neighbors Coalition",
    stance: "support",
    summary: "Verbatim quote supporting the legislation",
    draft_token: "token-hnc-99",
    bill_news_article_id: 88,
    text_version_id: 176,
    evidence_excerpt: "This bill establishes crucial tenant protections across Baltimore.",
    speaker_name: "Jordan Avery",
    speaker_role: "President and CEO",
    source_url: "https://www.thebaltimorebanner.com/politics-power/local-government/housing-bill-test",
    outlet_name: "The Baltimore Banner",
    article_title: "City Council Advances Major Housing Bill",
    excerpt_page: 2,
    excerpt_paragraph: 5,
    excerpt_offset: 340,
    excerpt_length: 67,
};

const sampleTestimonyPosition: IOrgPosition = {
    org_name: "Maryland Chamber of Commerce",
    stance: "oppose",
    summary: "Maryland Chamber opposes the regulatory burden imposed by the bill.",
    draft_token: "token-chamber-11",
    bill_news_article_id: null,
    text_version_id: null,
    evidence_excerpt: null,
};

describe("Adversarial Challenge: BillCreatorOrgPositionCard Citation and Button Mechanics", () => {
    beforeEach(() => {
        routerPost.mockReset();
        routerPatch.mockReset();
        routerReload.mockReset();
        notifyMock.mockReset();
        confirmMock.mockReset();
        usePageMock.mockReset();
        usePageMock.mockReturnValue({ props: {} });
    });

    afterEach(() => {
        cleanup();
    });

    it("adversarially verifies blockquote citation testid pattern with exact index data-testid='draft-org-position-news-excerpt-{index}'", () => {
        const { unmount } = render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={7}
                orgPosition={sampleNewsPosition}
                testimonyMissing={true}
                runInFlight={false}
            />,
        );

        const excerpt = screen.getByTestId("draft-org-position-news-excerpt-7");
        expect(excerpt).toBeInTheDocument();
        expect(excerpt.tagName).toBe("BLOCKQUOTE");
        expect(excerpt).toHaveTextContent("“This bill establishes crucial tenant protections across Baltimore.”");
        expect(excerpt).toHaveTextContent("— Jordan Avery, President and CEO");
        expect(excerpt).toHaveTextContent("p. 2, para. 5, char 340");

        const link = within(excerpt).getByRole("link", { name: "The Baltimore Banner" });
        expect(link).toHaveAttribute(
            "href",
            "https://www.thebaltimorebanner.com/politics-power/local-government/housing-bill-test",
        );
        expect(link).toHaveAttribute("target", "_blank");
        expect(link).toHaveAttribute("rel", "noopener noreferrer");

        unmount();

        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={42}
                orgPosition={sampleNewsPosition}
                testimonyMissing={true}
                runInFlight={false}
            />,
        );
        expect(screen.getByTestId("draft-org-position-news-excerpt-42")).toBeInTheDocument();
    });

    it("verifies numerical 0 values for page, paragraph, and offset are not swallowed by falsy checks", () => {
        const zeroOffsetPosition: IOrgPosition = {
            ...sampleNewsPosition,
            excerpt_page: 0,
            excerpt_paragraph: 0,
            excerpt_offset: 0,
        };

        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={0}
                orgPosition={zeroOffsetPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        const excerpt = screen.getByTestId("draft-org-position-news-excerpt-0");
        expect(excerpt).toHaveTextContent("p. 0, para. 0, char 0");
    });

    it("verifies link text fallback priority: outlet_name -> article_title -> source_url", () => {
        const { unmount } = render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={1}
                orgPosition={{ ...sampleNewsPosition, outlet_name: null }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.getByRole("link", { name: "City Council Advances Major Housing Bill" })).toBeInTheDocument();
        unmount();

        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={2}
                orgPosition={{ ...sampleNewsPosition, outlet_name: null, article_title: null }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(
            screen.getByRole("link", {
                name: "https://www.thebaltimorebanner.com/politics-power/local-government/housing-bill-test",
            }),
        ).toBeInTheDocument();
    });

    it("verifies attribution formatting when only speaker_name or speaker_role is present", () => {
        const { unmount } = render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={1}
                orgPosition={{ ...sampleNewsPosition, speaker_role: null }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.getByTestId("draft-org-position-news-excerpt-1")).toHaveTextContent("— Jordan Avery");
        expect(screen.getByTestId("draft-org-position-news-excerpt-1")).not.toHaveTextContent("President and CEO");
        unmount();

        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={2}
                orgPosition={{ ...sampleNewsPosition, speaker_name: null }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.getByTestId("draft-org-position-news-excerpt-2")).toHaveTextContent("— President and CEO");
        expect(screen.getByTestId("draft-org-position-news-excerpt-2")).not.toHaveTextContent("Jordan Avery");
    });

    it("adversarially verifies that when testimonyMissing is true, news draft has Approve, Edit, Reject ENABLED while testimony draft has Approve DISABLED", () => {
        const { container } = render(
            <>
                <BillCreatorOrgPositionCard
                    billId={100}
                    index={0}
                    orgPosition={sampleNewsPosition}
                    testimonyMissing={true}
                    runInFlight={false}
                />
                <BillCreatorOrgPositionCard
                    billId={100}
                    index={1}
                    orgPosition={sampleTestimonyPosition}
                    testimonyMissing={true}
                    runInFlight={false}
                />
            </>,
        );

        const cards = container.querySelectorAll("[data-testid^='org-position-card-']");
        expect(cards).toHaveLength(2);

        const newsCard = cards[0];
        const testimonyCard = cards[1];

        const newsApprove = within(newsCard as HTMLElement).getByTestId("btn-approve-org-position");
        const newsEdit = within(newsCard as HTMLElement).getByTestId("btn-edit-org-position");
        const newsReject = within(newsCard as HTMLElement).getByTestId("btn-reject-org-position");

        expect(newsApprove).not.toBeDisabled();
        expect(newsEdit).not.toBeDisabled();
        expect(newsReject).not.toBeDisabled();
        expect(newsApprove.getAttribute("aria-describedby") || "").not.toContain(NO_TESTIMONY_NOTICE_ID);

        const testimonyApprove = within(testimonyCard as HTMLElement).getByTestId("btn-approve-org-position");
        const testimonyEdit = within(testimonyCard as HTMLElement).getByTestId("btn-edit-org-position");
        const testimonyReject = within(testimonyCard as HTMLElement).getByTestId("btn-reject-org-position");

        expect(testimonyApprove).toBeDisabled();
        expect(testimonyEdit).not.toBeDisabled();
        expect(testimonyReject).not.toBeDisabled();
        expect(testimonyApprove.getAttribute("aria-describedby") || "").toContain(NO_TESTIMONY_NOTICE_ID);
    });

    it("verifies news draft Approve POST payload and Edit workflow", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={5}
                orgPosition={sampleNewsPosition}
                testimonyMissing={true}
                runInFlight={false}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        fireEvent.change(screen.getByTestId("input-edit-org-name"), {
            target: { value: "Harbor Neighbors Coalition (Amended)" },
        });
        fireEvent.change(screen.getByTestId("select-edit-stance"), { target: { value: "neutral" } });
        fireEvent.change(screen.getByTestId("textarea-edit-summary"), {
            target: { value: "Updated summary text." },
        });
        fireEvent.click(screen.getByText("Apply edits"));

        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/100/approve_org_position",
            expect.objectContaining({
                org_name: "Harbor Neighbors Coalition (Amended)",
                support: "neutral",
                summary: "Updated summary text.",
                index: 5,
                draft_org_name: "Harbor Neighbors Coalition",
                draft_token: "token-hnc-99",
            }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("verifies runInFlight disables Approve even on news draft", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={0}
                orgPosition={sampleNewsPosition}
                testimonyMissing={false}
                runInFlight={true}
            />,
        );

        const approveBtn = screen.getByTestId("btn-approve-org-position");
        expect(approveBtn).toBeDisabled();
        expect(approveBtn.getAttribute("aria-describedby")).toContain(RUN_IN_FLIGHT_NOTICE_ID);
    });

    it("verifies evidence_retracted_at disables Approve and renders retraction notice on news draft", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={0}
                orgPosition={{ ...sampleNewsPosition, evidence_retracted_at: "2026-10-26T12:00:00Z" }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        const approveBtn = screen.getByTestId("btn-approve-org-position");
        expect(approveBtn).toBeDisabled();
        expect(screen.getByTestId("org-position-evidence-retracted")).toBeInTheDocument();
    });

    it("verifies unacknowledged testimony left out does NOT disable news draft Approve", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={100}
                index={0}
                orgPosition={sampleNewsPosition}
                testimonyMissing={false}
                testimonyLeftOutUnacknowledged={true}
                runInFlight={false}
            />,
        );

        const approveBtn = screen.getByTestId("btn-approve-org-position");
        expect(approveBtn).not.toBeDisabled();
        expect(approveBtn.getAttribute("aria-describedby") || "").not.toContain(TESTIMONY_COVERAGE_NOTICE_ID);
    });
});

describe("Adversarial Challenge: LlmSummaryOrgPositions Notice Suppression", () => {
    beforeEach(() => {
        usePageMock.mockReset();
        usePageMock.mockReturnValue({ props: {} });
    });

    afterEach(() => {
        cleanup();
    });

    it("suppresses noTestimony notice when 100% of drafts are news-sourced and hasTestimony is false", () => {
        const positions: TDraftOrgPosition[] = [
            { ...sampleNewsPosition, rawIndex: 0 },
            {
                ...sampleNewsPosition,
                org_name: "Baltimore Teachers Union",
                bill_news_article_id: 89,
                text_version_id: 178,
                rawIndex: 1,
            },
        ];

        render(
            <LlmSummaryOrgPositions billId={100} orgPositions={positions} hasTestimony={false} runInFlight={false} />,
        );

        expect(screen.queryByTestId("llm-no-testimony")).toBeNull();
        expect(screen.getByText("Harbor Neighbors Coalition")).toBeInTheDocument();
        expect(screen.getByText("Baltimore Teachers Union")).toBeInTheDocument();
    });

    it("displays noTestimony notice when at least one draft is testimony-sourced without testimony", () => {
        const positions: TDraftOrgPosition[] = [
            { ...sampleNewsPosition, rawIndex: 0 },
            { ...sampleTestimonyPosition, rawIndex: 1 },
        ];

        render(
            <LlmSummaryOrgPositions billId={100} orgPositions={positions} hasTestimony={false} runInFlight={false} />,
        );

        const notice = screen.getByTestId("llm-no-testimony");
        expect(notice).toBeInTheDocument();
        expect(notice).toHaveTextContent(/no public testimony available for this bill/i);
    });

    it("displays noTestimony empty state when there are zero drafts and hasTestimony is false", () => {
        render(<LlmSummaryOrgPositions billId={100} orgPositions={[]} hasTestimony={false} runInFlight={false} />);

        expect(screen.getByTestId("llm-no-testimony")).toBeInTheDocument();
    });
});

describe("Adversarial Challenge: BillCreatorTestimonyPositions Destructive Warnings Isolation", () => {
    function buildBill(overrides: {
        supplemental_testimony?: string | null;
        draft_org_positions?: IOrgPosition[];
        has_testimony?: boolean;
    }) {
        const bill_llm_provisioning: IBillLlmProvisioning = {
            has_testimony: overrides.has_testimony ?? true,
            testimony_attachments: null,
            llm_provider: "claude",
            citations_valid: null,
            invalid_citations: null,
            generation_status: "completed",
            generation_error: null,
            llm_summary: "Summary content",
            llm_full_breakdown: "Breakdown content",
            supplemental_testimony: overrides.supplemental_testimony ?? null,
            draft_org_positions: overrides.draft_org_positions ?? [],
            stale: false,
            reclaimable: false,
            paste_owns_summary_run: false,
            stale_change_kind: null,
            stale_change_at: null,
            llm_generated_at: new Date().toISOString(),
        };

        return {
            id: 100,
            external_id: "SB200",
            summary: "Published summary",
            bill_llm_provisioning,
            bill_pipeline_refresh: null,
        };
    }

    beforeEach(() => {
        routerPatch.mockClear();
        routerPost.mockClear();
        confirmMock.mockReset();
        confirmMock.mockResolvedValue(true);
        usePageMock.mockReset();
    });

    afterEach(() => {
        cleanup();
    });

    it("adversarially verifies saving supplemental testimony does NOT trigger confirmation when only news drafts exist", async () => {
        usePageMock.mockReturnValue({
            props: {
                bill: buildBill({
                    supplemental_testimony: "Prior testimony",
                    draft_org_positions: [sampleNewsPosition],
                }),
            },
        });

        render(<BillCreatorTestimonyPositions />);

        const textarea = screen.getByTestId("textarea-supplemental-testimony");
        await act(async () => {
            fireEvent.change(textarea, { target: { value: "New replaced testimony" } });
        });
        await act(async () => {
            fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
        });

        expect(confirmMock).not.toHaveBeenCalled();
        expect(routerPatch).toHaveBeenCalledWith(
            "/bills/100/supplemental_testimony",
            { supplemental_testimony: "New replaced testimony" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("adversarially verifies clearing supplemental testimony does NOT trigger confirmation when only news drafts exist", async () => {
        usePageMock.mockReturnValue({
            props: {
                bill: buildBill({
                    supplemental_testimony: "Prior testimony",
                    draft_org_positions: [sampleNewsPosition],
                }),
            },
        });

        render(<BillCreatorTestimonyPositions />);

        await act(async () => {
            fireEvent.click(screen.getByTestId("btn-clear-supplemental-testimony"));
        });

        expect(confirmMock).not.toHaveBeenCalled();
        expect(routerPatch).toHaveBeenCalledWith(
            "/bills/100/supplemental_testimony",
            { clear_supplemental_testimony: true },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("adversarially verifies clearing supplemental testimony DOES trigger confirmation naming only testimony drafts on mixed bill", async () => {
        usePageMock.mockReturnValue({
            props: {
                bill: buildBill({
                    supplemental_testimony: "Prior testimony",
                    draft_org_positions: [sampleNewsPosition, sampleTestimonyPosition],
                }),
            },
        });

        render(<BillCreatorTestimonyPositions />);

        await act(async () => {
            fireEvent.click(screen.getByTestId("btn-clear-supplemental-testimony"));
        });

        expect(confirmMock).toHaveBeenCalledTimes(1);
        const options = confirmMock.mock.calls[0][0];
        expect(options.description).toContain("1 draft position on this bill was written from");
        expect(options.description).not.toContain("2 draft positions");
        expect(routerPatch).toHaveBeenCalled();
    });

    it("adversarially verifies saving replacement testimony DOES trigger confirmation naming only testimony drafts on mixed bill", async () => {
        usePageMock.mockReturnValue({
            props: {
                bill: buildBill({
                    supplemental_testimony: "Prior testimony",
                    draft_org_positions: [
                        sampleNewsPosition,
                        sampleTestimonyPosition,
                        { ...sampleTestimonyPosition, org_name: "AFL-CIO" },
                    ],
                }),
            },
        });

        render(<BillCreatorTestimonyPositions />);

        const textarea = screen.getByTestId("textarea-supplemental-testimony");
        await act(async () => {
            fireEvent.change(textarea, { target: { value: "Totally new testimony text" } });
        });
        await act(async () => {
            fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
        });

        expect(confirmMock).toHaveBeenCalledTimes(1);
        const options = confirmMock.mock.calls[0][0];
        expect(options.description).toContain("2 draft positions on this bill were written from");
        expect(options.description).not.toContain("3 draft positions");
        expect(routerPatch).toHaveBeenCalled();
    });
});
