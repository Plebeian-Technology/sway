import { fireEvent, render as rtlRender, screen, within } from "@testing-library/react";
import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";
import { useState } from "react";
import LlmSummaryOrgPositions from "app/frontend/components/admin/creator/llm-summary/LlmSummaryOrgPositions";
import {
    IOrgPosition,
    ITestimonyCampaignDraft,
    TDraftOrgPosition,
} from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[private-individual-guard-override#Approve-anyway lives behind the app-wide confirm dialog]]
const render = (ui: React.ReactElement) => rtlRender(ui, { wrapper: ConfirmProvider });

// @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
const usePageMock = vi.fn<() => { props: Record<string, unknown> }>();
const routerReload = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: {
        post: vi.fn<(...args: unknown[]) => void>(),
        reload: (...args: unknown[]) => routerReload(...args),
    },
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorOrgPositionCard", () => {
    const StubOrgPositionCard: React.FC<{
        index: number;
        orgPosition: IOrgPosition;
        testimonyMissing: boolean;
        testimonyLeftOutUnacknowledged?: boolean;
    }> = ({ index, orgPosition, testimonyMissing, testimonyLeftOutUnacknowledged }) => {
        const [draft, setDraft] = useState<string>(orgPosition.summary);
        return (
            <div
                data-testid="org-position-card"
                data-index={index}
                data-testimony-missing={String(testimonyMissing)}
                data-testimony-left-out-unacknowledged={String(!!testimonyLeftOutUnacknowledged)}
            >
                {orgPosition.org_name}
                <input
                    aria-label={`edit ${orgPosition.org_name}`}
                    value={draft}
                    onChange={(e) => setDraft(e.target.value)}
                />
            </div>
        );
    };
    return { default: StubOrgPositionCard };
});

const baseProps = {
    billId: 42,
    // @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
    runInFlight: false,
};

describe("LlmSummaryOrgPositions", () => {
    beforeEach(() => {
        usePageMock.mockReset();
        usePageMock.mockReturnValue({ props: {} });
    });

    it("renders the no-testimony empty state when orgPositions is empty and hasTestimony is false", () => {
        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={false} />);

        expect(screen.getByTestId("llm-no-testimony")).toBeInTheDocument();
        expect(
            screen.getByText(
                "No public testimony available for this bill — positions are not generated without testimony. Fill in the Supplemental testimony field on this tab and click Save testimony to enable generation.",
            ),
        ).toBeInTheDocument();
        expect(screen.queryByText("No draft positions generated.")).toBeNull();
    });

    // @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
    it("tells an operator with retracted drafts to regenerate, not to paste", () => {
        const positions: TDraftOrgPosition[] = [
            {
                org_name: "Org A",
                stance: "support",
                summary: "supports the bill",
                rawIndex: 0,
                evidence_retracted_at: "2026-08-01T00:00:00Z",
            },
        ];

        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

        expect(screen.getByTestId("llm-no-testimony")).toHaveTextContent("does not restore them");
        expect(screen.getByTestId("llm-no-testimony")).not.toHaveTextContent("Paste the testimony back");
    });

    // The other half. Without the mark the bill simply has no testimony, and
    // pasting some in really is a way forward — so the older advice has to
    // survive rather than be replaced everywhere.
    it("still offers the paste route when the drafts carry no mark", () => {
        const positions: TDraftOrgPosition[] = [
            { org_name: "Org A", stance: "support", summary: "supports the bill", rawIndex: 0 },
        ];

        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

        // @lat: [[llm-summary-no-testimony-notice-copy#Test note: naming the field, not just the click]]
        expect(screen.getByTestId("llm-no-testimony")).toHaveTextContent("Paste the testimony back");
        expect(screen.getByTestId("llm-no-testimony")).toHaveTextContent(/click Save testimony/i);
    });

    // @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
    it("keeps the paste route when only some drafts are marked", () => {
        const positions: TDraftOrgPosition[] = [
            {
                org_name: "Org A",
                stance: "support",
                summary: "supports the bill",
                rawIndex: 0,
                evidence_retracted_at: "2026-08-01T00:00:00Z",
            },
            { org_name: "Org B", stance: "oppose", summary: "opposes the bill", rawIndex: 1 },
        ];

        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

        // @lat: [[llm-summary-no-testimony-notice-copy#Test note: naming the field, not just the click]]
        expect(screen.getByTestId("llm-no-testimony")).toHaveTextContent("Paste the testimony back");
        expect(screen.getByTestId("llm-no-testimony")).toHaveTextContent(/click Save testimony/i);
    });

    // @lat: [[llm-summary-org-positions-list#testimonyMissing defaults to "no testimony"]]
    it("treats an absent answer as no testimony, not as testimony", () => {
        const positions: TDraftOrgPosition[] = [
            { org_name: "Org A", stance: "support", summary: "supports the bill", rawIndex: 0 },
        ];

        render(
            <LlmSummaryOrgPositions
                {...baseProps}
                orgPositions={positions}
                hasTestimony={undefined as unknown as boolean}
            />,
        );

        expect(screen.getByTestId("llm-no-testimony")).toBeInTheDocument();
        expect(screen.getByTestId("org-position-card")).toHaveAttribute("data-testimony-missing", "true");
    });

    it("renders the existing ran-but-empty copy (unchanged testid) when orgPositions is empty and hasTestimony is true", () => {
        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={true} />);

        expect(screen.getByText("No draft positions generated.")).toBeInTheDocument();
        expect(screen.queryByTestId("llm-no-testimony")).toBeNull();
    });

    it("renders position cards and no empty state when orgPositions is non-empty and testimony is present", () => {
        const positions: TDraftOrgPosition[] = [
            { org_name: "Org A", stance: "support", summary: "supports the bill", rawIndex: 0 },
        ];
        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={true} />);

        expect(screen.getByTestId("org-position-card")).toHaveTextContent("Org A");
        expect(screen.queryByTestId("llm-no-testimony")).toBeNull();
        expect(screen.queryByText("No draft positions generated.")).toBeNull();
    });

    // @lat: [[llm-summary-no-testimony-notice-copy#Why the component moved out of the empty-list branch]]
    describe("no testimony WITH surviving drafts (A2-CR-01 / C2-CR-01)", () => {
        const positions: TDraftOrgPosition[] = [
            { org_name: "Org A", stance: "support", summary: "supports the bill", rawIndex: 0 },
        ];

        it("renders the no-testimony notice above the cards", () => {
            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

            const notice = screen.getByTestId("llm-no-testimony");
            expect(notice).toBeInTheDocument();
            expect(notice.textContent).toMatch(/no public testimony/i);
            expect(notice.textContent).toMatch(/cannot be approved/i);
            expect(screen.getByTestId("org-position-card")).toHaveTextContent("Org A");
        });

        // @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
        it("renders the notice with the id the cards' aria-describedby points at", () => {
            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

            expect(screen.getByTestId("llm-no-testimony").id).toBe("llm-no-testimony-notice");
        });

        it("does not fall back to the ran-but-empty copy", () => {
            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

            expect(screen.queryByText("No draft positions generated.")).toBeNull();
        });

        // @lat: [[bill-creator-org-position-card#Why the notice AND the button both react to no-testimony]]
        it("tells every card the bill has no testimony", () => {
            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={false} />);

            expect(screen.getByTestId("org-position-card")).toHaveAttribute("data-testimony-missing", "true");
        });

        it("tells the cards nothing is missing while testimony is present", () => {
            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={true} />);

            expect(screen.getByTestId("org-position-card")).toHaveAttribute("data-testimony-missing", "false");
        });
    });

    // The card gets the slot in the raw draft_org_positions array, which is how
    // the server identifies a draft — not the position in this filtered list.
    it("passes each position's rawIndex to the card as `index`", () => {
        const positions: TDraftOrgPosition[] = [
            { org_name: "Org A", stance: "support", summary: "supports", rawIndex: 1 },
            { org_name: "Org B", stance: "oppose", summary: "opposes", rawIndex: 2 },
        ];
        render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={true} />);

        expect(screen.getAllByTestId("org-position-card").map((c) => c.getAttribute("data-index"))).toEqual(["1", "2"]);
    });

    // @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
    describe("a sibling deletion does not remount the surviving cards (C1-WR-04)", () => {
        const three: TDraftOrgPosition[] = [
            { org_name: "Org A", stance: "support", summary: "a", draft_token: "aaa111", rawIndex: 0 },
            { org_name: "Org B", stance: "oppose", summary: "b", draft_token: "bbb222", rawIndex: 1 },
            { org_name: "Org C", stance: "neutral", summary: "c", draft_token: "ccc333", rawIndex: 2 },
        ];
        // What the follow-up GET returns after Org A is rejected.
        const afterRejectingTheFirst: TDraftOrgPosition[] = [
            { org_name: "Org B", stance: "oppose", summary: "b", draft_token: "bbb222", rawIndex: 0 },
            { org_name: "Org C", stance: "neutral", summary: "c", draft_token: "ccc333", rawIndex: 1 },
        ];

        it("keeps a third card's unsaved edit when the first is rejected", () => {
            const { rerender } = render(
                <LlmSummaryOrgPositions {...baseProps} orgPositions={three} hasTestimony={true} />,
            );

            fireEvent.change(screen.getByLabelText("edit Org C"), {
                target: { value: "rewritten paragraph the operator just typed" },
            });

            rerender(
                <LlmSummaryOrgPositions {...baseProps} orgPositions={afterRejectingTheFirst} hasTestimony={true} />,
            );

            expect(screen.getByLabelText("edit Org C")).toHaveValue("rewritten paragraph the operator just typed");
        });

        // rawIndex is the SERVER's id for the entry and must keep reaching the
        // card unchanged. Only the React key stopped using it.
        it("still hands the card its shifted rawIndex", () => {
            const { rerender } = render(
                <LlmSummaryOrgPositions {...baseProps} orgPositions={three} hasTestimony={true} />,
            );
            rerender(
                <LlmSummaryOrgPositions {...baseProps} orgPositions={afterRejectingTheFirst} hasTestimony={true} />,
            );

            expect(screen.getAllByTestId("org-position-card").map((c) => c.getAttribute("data-index"))).toEqual([
                "0",
                "1",
            ]);
        });

        // @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
        it("survives a sibling deletion even without draft_token", () => {
            const untokened = three.map(({ draft_token: _drop, ...rest }) => rest);
            const { rerender } = render(
                <LlmSummaryOrgPositions {...baseProps} orgPositions={untokened} hasTestimony={true} />,
            );

            fireEvent.change(screen.getByLabelText("edit Org C"), { target: { value: "typed" } });

            rerender(
                <LlmSummaryOrgPositions
                    {...baseProps}
                    orgPositions={untokened.slice(1).map((p, i) => ({ ...p, rawIndex: i }))}
                    hasTestimony={true}
                />,
            );

            expect(screen.getByLabelText("edit Org C")).toHaveValue("typed");
        });
    });

    // The coverage notice reads testimony_coverage straight off
    // usePage, not a prop — see the mock at the top of this file. The object below carries every
    // field Testimony::CoverageReport::Result returns, since the notice now branches on `state`
    // and the letter counts, not just the two character totals.
    describe("the testimony coverage notice", () => {
        const nothingLeftOutCoverage = {
            state: "cleaned",
            coverage_gap: false,
            total_chars: 900,
            reached_chars: 900,
            removed_chars: 0,
            repair_added_chars: 0,
            left_out_chars: 0,
            total_letters: 5,
            reached_letters: 5,
            removed_letters: 0,
            left_out_letters: 0,
            individual_letter_count: 0,
            attachment_cut_count: 0,
            attachment_cut_cap: null,
            paste_present: false,
            paste_chars: 0,
            paste_share_of_limit: null,
            displaced_letter_count: 0,
            digest: "a".repeat(64),
            acknowledged: false,
            acknowledged_by_email: null,
            acknowledged_at: null,
        };

        it("renders the notice when testimony_coverage is present on the page", () => {
            usePageMock.mockReturnValue({ props: { testimony_coverage: nothingLeftOutCoverage } });

            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={true} />);

            expect(screen.getByTestId("llm-testimony-coverage-notice")).toBeInTheDocument();
        });

        it("renders nothing for the notice when testimony_coverage is absent from the page props", () => {
            usePageMock.mockReturnValue({ props: {} });

            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={true} />);

            expect(screen.queryByTestId("llm-testimony-coverage-notice")).toBeNull();
        });

        // The fourth reason Approve is off is derived here, once, from the same
        // testimony_coverage prop the notice reads — not a parallel gate on the card.
        it("does not pass the fourth Approve-disabled reason down to the cards when nothing was left out", () => {
            usePageMock.mockReturnValue({ props: { testimony_coverage: nothingLeftOutCoverage } });
            const positions: TDraftOrgPosition[] = [
                { org_name: "Org A", stance: "support", summary: "supports the bill", rawIndex: 0 },
            ];

            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={true} />);

            expect(screen.getByTestId("org-position-card")).toHaveAttribute(
                "data-testimony-left-out-unacknowledged",
                "false",
            );
        });

        it("passes the fourth Approve-disabled reason down to every card when something was left out and not acknowledged", () => {
            usePageMock.mockReturnValue({
                props: {
                    testimony_coverage: {
                        ...nothingLeftOutCoverage,
                        coverage_gap: true,
                        left_out_letters: 1,
                        reached_letters: 4,
                    },
                },
            });
            const positions: TDraftOrgPosition[] = [
                { org_name: "Org A", stance: "support", summary: "supports the bill", rawIndex: 0 },
            ];

            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={positions} hasTestimony={true} />);

            expect(screen.getByTestId("org-position-card")).toHaveAttribute(
                "data-testimony-left-out-unacknowledged",
                "true",
            );
        });
    });

    // testimony_claimed_affiliations reads straight off usePage, the
    // same top-level-prop pattern testimony_campaign_drafts already established — see the mock at
    // the top of this file. BillCreatorClaimedAffiliationCard is not mocked here, so this exercises
    // the real card's own empty-evidence guard too.
    describe("the claimed-affiliation cards", () => {
        it("renders a card for each claimed affiliation the page carries", () => {
            usePageMock.mockReturnValue({
                props: {
                    testimony_claimed_affiliations: [
                        {
                            position: 3,
                            phrase: "president of the Baltimore Transit Equity Coalition",
                            role: "president",
                            sender: "jane@example.com",
                        },
                    ],
                },
            });

            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={true} />);

            expect(screen.getByTestId("claimed-affiliation-card-claimed-affiliation-3")).toBeInTheDocument();
        });

        it("renders no claimed-affiliation card when the page carries none", () => {
            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={true} />);

            expect(screen.queryByTestId("claimed-affiliation-stamp")).not.toBeInTheDocument();
        });
    });

    describe("the campaign letter bundles", () => {
        const campaignDraft = (contentHash: string): ITestimonyCampaignDraft => ({
            content_hash: contentHash,
            sender_count: 2,
            letter_count: 2,
            added_words_characters: 0,
            senders_added_words_left_out: 0,
            domain: null,
        });

        it("hands each card the bundle carrying its own content hash, not the one in its position", () => {
            usePageMock.mockReturnValue({
                props: {
                    testimony_campaign_drafts: [campaignDraft("aaa111"), campaignDraft("bbb222")],
                    testimony_campaign_letters: [
                        {
                            content_hash: "bbb222",
                            letters: [
                                {
                                    position: 4,
                                    text: "The second campaign's letter body.",
                                    sender_address: "jane@example.com",
                                    sender_domain: "example.com",
                                    repeat: false,
                                },
                            ],
                        },
                    ],
                },
            });

            render(<LlmSummaryOrgPositions {...baseProps} orgPositions={[]} hasTestimony={true} />);

            const second = screen.getByTestId("campaign-position-card-campaign-bbb222");
            fireEvent.click(within(second).getByTestId("btn-campaign-letters-disclosure"));

            expect(within(second).getByText("The second campaign's letter body.")).toBeInTheDocument();
            expect(routerReload).not.toHaveBeenCalled();

            const first = screen.getByTestId("campaign-position-card-campaign-aaa111");
            fireEvent.click(within(first).getByTestId("btn-campaign-letters-disclosure"));

            expect(within(first).queryByText("The second campaign's letter body.")).not.toBeInTheDocument();
            expect(within(first).getByTestId("campaign-letters-loading")).toBeInTheDocument();
            expect(routerReload).toHaveBeenCalledTimes(1);
        });
    });

    describe("news-sourced draft notice suppression", () => {
        const newsDraft1: TDraftOrgPosition = {
            org_name: "Org A",
            stance: "support",
            summary: "supports",
            bill_news_article_id: 101,
            text_version_id: 201,
            evidence_excerpt: "We support",
            rawIndex: 0,
        };
        const newsDraft2: TDraftOrgPosition = {
            org_name: "Org B",
            stance: "oppose",
            summary: "opposes",
            bill_news_article_id: 102,
            text_version_id: 202,
            evidence_excerpt: "We oppose",
            rawIndex: 1,
        };
        const testimonyDraft: TDraftOrgPosition = {
            org_name: "Org C",
            stance: "support",
            summary: "testimony support",
            bill_news_article_id: null,
            rawIndex: 2,
        };

        it("suppresses the no-testimony notice when all drafts are news-sourced", () => {
            render(
                <LlmSummaryOrgPositions {...baseProps} orgPositions={[newsDraft1, newsDraft2]} hasTestimony={false} />,
            );

            expect(screen.queryByTestId("llm-no-testimony")).toBeNull();
            expect(screen.getAllByTestId("org-position-card")).toHaveLength(2);
        });

        it("renders the no-testimony notice when drafts are mixed (some news-sourced, some testimony-sourced)", () => {
            render(
                <LlmSummaryOrgPositions
                    {...baseProps}
                    orgPositions={[newsDraft1, testimonyDraft]}
                    hasTestimony={false}
                />,
            );

            expect(screen.getByTestId("llm-no-testimony")).toBeInTheDocument();
            expect(screen.getAllByTestId("org-position-card")).toHaveLength(2);
        });
    });
});
