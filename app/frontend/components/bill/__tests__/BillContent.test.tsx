// @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const MOCK_GENERIC_PORTAL_URLS = [
    "https://baltimore.legistar.com",
    "https://baltimore.legistar.com/LegislationSearch.aspx",
    "https://congress.gov",
    "https://www.congress.gov",
    "https://mgaleg.maryland.gov",
    "https://mgaleg.maryland.gov/mgawebsite",
];

let mockPageProps: Record<string, unknown> = {
    user: null,
    sway_locale: {
        generic_portal_urls: MOCK_GENERIC_PORTAL_URLS,
    },
};

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, ...props }: { children: React.ReactNode }) => <a {...props}>{children}</a>,
    usePage: () => ({
        props: mockPageProps,
    }),
    router: {
        reload: vi.fn<() => void>(),
    },
    useForm: (initial: unknown) => ({
        data: initial,
        setData: vi.fn<(key?: string, value?: unknown) => void>(),
        post: vi.fn<() => void>(),
        reset: vi.fn<() => void>(),
        processing: false,
        errors: {},
    }),
}));

import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocaleSlug: vi.fn<() => string | undefined>(() => "baltimore-maryland-united_states"),
}));

vi.mock("app/frontend/components/bill/charts/BillChartsPanel", () => ({
    default: () => <div data-testid="mock-charts" />,
}));
vi.mock("app/frontend/components/bill/charts/BillAffinityPanel", () => ({
    default: () => <div data-testid="mock-affinity" />,
}));
vi.mock("app/frontend/components/bill/EmailLegislatorsModal", () => ({
    default: () => <div data-testid="mock-email-modal" />,
}));
vi.mock("app/frontend/components/bill/BillAsIntroduced", () => ({
    default: () => <div data-testid="mock-as-introduced" />,
}));

import BillContent from "app/frontend/components/bill/BillContent";

const BASE_BILL: sway.IBill = {
    id: 101,
    external_id: "24-0001",
    title: "Ordinance on Street Trees",
    summary: "Requires planting native street trees across the city.",
    summary_ai_unreviewed: true,
    status: "passed",
    link: "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
    sway_locale_id: 1,
    legislator_id: 10,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
} as unknown as sway.IBill;

afterEach(() => {
    cleanup();
    mockPageProps = {
        user: null,
        sway_locale: {
            generic_portal_urls: MOCK_GENERIC_PORTAL_URLS,
        },
    };
});

describe("BillContent — Official Source Link Presentation", () => {
    // Resolve lazy markdown renderer chunk before any example is on the clock.
    // @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
    beforeAll(async () => {
        await import("app/frontend/components/bill/BillSummaryMarkdown");
    });

    it("Case 1: renders the external link button when bill carries a valid detail link", async () => {
        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        const sourceLink = screen.getByRole("link", { name: /Baltimore Legistar/i });
        expect(sourceLink).toBeInTheDocument();
        expect(sourceLink).toHaveAttribute(
            "href",
            "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
        );
        expect(screen.queryByTestId("no-source-link")).not.toBeInTheDocument();

        const summaryNoticeLink = await screen.findByTestId("bill-source-text-link", {}, { timeout: 5000 });
        expect(summaryNoticeLink).toBeInTheDocument();
        expect(summaryNoticeLink).toHaveAttribute(
            "href",
            "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
        );
        expect(screen.queryByTestId("summary-no-source-link")).not.toBeInTheDocument();
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
    });

    it("Case 2: suppresses the button and displays unavailable copy when link is null or empty", async () => {
        const unlinkedBill = { ...BASE_BILL, link: null };
        render(<BillContent bill={unlinkedBill} organizations={[]} />);

        expect(screen.queryByRole("link", { name: /Baltimore Legistar/i })).not.toBeInTheDocument();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeInTheDocument();
        expect(notice).toHaveTextContent(PARITY_COPY.bill.officialSourceUnavailable);

        const summaryNotice = await screen.findByTestId("summary-no-source-link", {}, { timeout: 5000 });
        expect(summaryNotice).toBeInTheDocument();
        expect(summaryNotice).toHaveTextContent(PARITY_COPY.bill.officialSourceUnavailable);
        expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();

        const reportBtn = screen.getByTestId("btn-report-inaccurate-summary");
        expect(reportBtn).toBeInTheDocument();
        expect(screen.queryByTestId("report-summary-form")).not.toBeInTheDocument();
        fireEvent.click(reportBtn);
        expect(screen.getByTestId("report-summary-form")).toBeInTheDocument();
    });

    it("Case 3: suppresses the button and displays unavailable copy when link is generic search URL", async () => {
        const genericBill = {
            ...BASE_BILL,
            link: "https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced",
        };
        render(<BillContent bill={genericBill} organizations={[]} />);

        expect(screen.queryByRole("link", { name: /Baltimore Legistar/i })).not.toBeInTheDocument();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeInTheDocument();
        expect(notice).toHaveTextContent(PARITY_COPY.bill.officialSourceUnavailable);

        const summaryNotice = await screen.findByTestId("summary-no-source-link", {}, { timeout: 5000 });
        expect(summaryNotice).toBeInTheDocument();
        expect(summaryNotice).toHaveTextContent(PARITY_COPY.bill.officialSourceUnavailable);
        expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
    });

    it("Case 4: suppresses the button when link is generic portal URL with trailing slash", async () => {
        const trailingSlashBill = {
            ...BASE_BILL,
            link: "https://congress.gov/",
        };
        render(<BillContent bill={trailingSlashBill} organizations={[]} />);

        expect(screen.queryByRole("link", { name: /Baltimore Legistar/i })).not.toBeInTheDocument();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeInTheDocument();
        expect(notice).toHaveTextContent(PARITY_COPY.bill.officialSourceUnavailable);

        const summaryNotice = await screen.findByTestId("summary-no-source-link", {}, { timeout: 5000 });
        expect(summaryNotice).toBeInTheDocument();
        expect(summaryNotice).toHaveTextContent(PARITY_COPY.bill.officialSourceUnavailable);
        expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
    });

    it("Case 5: renders 'Official Source' fallback label for an unknown/fourth locale", () => {
        vi.mocked(useSwayLocaleSlug).mockReturnValueOnce("annapolis-maryland-united_states");
        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        const sourceLink = screen.getByRole("link", { name: /Official Source/i });
        expect(sourceLink).toBeInTheDocument();
        expect(sourceLink).toHaveAttribute(
            "href",
            "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
        );
        expect(screen.queryByTestId("no-source-link")).not.toBeInTheDocument();
    });
});

describe("BillContent — Related News Articles Integration", () => {
    it("renders RelatedNewsArticles when approved articles are attached to bill", () => {
        const billWithNews = {
            ...BASE_BILL,
            related_articles: [
                {
                    id: 55,
                    title: "Tree Canopy Expansion Supported by Community",
                    url: "https://baltimoresun.com/tree-canopy-2026",
                    outlet_name: "The Baltimore Sun",
                    published_at: "2026-02-15T09:00:00Z",
                    article_kind: "reporting",
                    match_kind: "direct",
                } as sway.INewsArticle,
            ],
        };
        render(<BillContent bill={billWithNews} organizations={[]} />);

        const section = screen.getByTestId("related-news-articles");
        expect(section).toBeInTheDocument();
        const link = screen.getByRole("link", { name: /Tree Canopy Expansion Supported by Community/i });
        expect(link).toHaveAttribute("href", "https://baltimoresun.com/tree-canopy-2026");
    });

    it("renders no related news elements when related_articles is empty or omitted", () => {
        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        expect(screen.queryByTestId("related-news-articles")).toBeNull();
    });
});

describe("BillContent — News Article Testimony Integration", () => {
    it("renders attributed news testimony in Support and Oppose cards alongside organizational positions", () => {
        const billWithTestimony: sway.IBill = {
            ...BASE_BILL,
            news_testimonies: [
                {
                    id: 1,
                    author_name: "Marcus Vance",
                    outlet_name: "The Baltimore Sun",
                    url: "https://baltimoresun.com/opinion/support-trees",
                    stance: "support",
                    argument: "Urban forestry directly reduces summer heat island effects.",
                },
                {
                    id: 2,
                    author_name: "Elena Rostova",
                    outlet_name: "The Baltimore Banner",
                    url: "https://baltimorebanner.com/opinion/oppose-trees",
                    stance: "oppose",
                    argument: "Mandatory tree setbacks impose unfunded maintenance costs on small businesses.",
                },
            ],
        };

        render(<BillContent bill={billWithTestimony} organizations={[]} />);

        const supportCommentary = screen.getByText("Urban forestry directly reduces summer heat island effects.");
        expect(supportCommentary).toBeInTheDocument();
        expect(screen.getByText("By Marcus Vance")).toBeInTheDocument();

        const opposeCommentary = screen.getByText(
            "Mandatory tree setbacks impose unfunded maintenance costs on small businesses.",
        );
        expect(opposeCommentary).toBeInTheDocument();
        expect(screen.getByText("By Elena Rostova")).toBeInTheDocument();

        expect(screen.getByText(PARITY_COPY.org.noSupport)).toBeInTheDocument();
        expect(screen.getByText(PARITY_COPY.org.noOppose)).toBeInTheDocument();
    });

    it("renders zero news testimony DOM elements when news_testimonies is omitted or empty", () => {
        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        expect(screen.queryByTestId("news-article-testimony")).toBeNull();
    });
});

describe("BillContent — Share Bill Action", () => {
    it("renders the share bill button when userVote is undefined", () => {
        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
    });

    it("renders the share bill button when userVote is present", () => {
        const userVote: sway.IUserVote = {
            id: 1,
            bill_id: BASE_BILL.id,
            user_id: 1,
            position: "support",
        } as unknown as sway.IUserVote;

        render(<BillContent bill={BASE_BILL} organizations={[]} userVote={userVote} />);

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
    });

    it("renders the share bill button and suppresses email modal when bill is inactive and userVote is present", () => {
        const inactiveBill = { ...BASE_BILL, active: false };
        const userVote: sway.IUserVote = {
            id: 1,
            bill_id: BASE_BILL.id,
            user_id: 1,
            position: "support",
        } as unknown as sway.IUserVote;

        render(<BillContent bill={inactiveBill} organizations={[]} userVote={userVote} />);

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
        expect(screen.queryByTestId("mock-email-modal")).toBeNull();
    });

    it("renders both share bill button and email modal when bill is active and userVote is present", () => {
        const activeBill = { ...BASE_BILL, active: true };
        const userVote: sway.IUserVote = {
            id: 1,
            bill_id: BASE_BILL.id,
            user_id: 1,
            position: "support",
        } as unknown as sway.IUserVote;

        render(<BillContent bill={activeBill} organizations={[]} userVote={userVote} />);

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
        expect(screen.getByTestId("mock-email-modal")).toBeInTheDocument();
    });
});

describe("BillContent — Public Testimony Section Integration", () => {
    it("renders zero public testimony elements when counts are omitted or zero", () => {
        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        expect(screen.queryByTestId("public-testimony-section")).toBeNull();
    });

    it("renders PublicTestimonySection when public_testimony_counts is passed as a prop with total > 0", () => {
        const counts: sway.IPublicTestimonyCounts = {
            total: 10,
            support: 6,
            oppose: 3,
            neutral: 1,
        };

        render(<BillContent bill={BASE_BILL} organizations={[]} public_testimony_counts={counts} />);

        const section = screen.getByTestId("public-testimony-section");
        expect(section).toBeInTheDocument();
        expect(screen.getByText(PARITY_COPY.publicTestimony.section.heading)).toBeInTheDocument();
        expect(screen.getByText(PARITY_COPY.publicTestimony.section.subtitle(10))).toBeInTheDocument();
        expect(screen.getByTestId("pill-support")).toHaveTextContent(
            `6 ${PARITY_COPY.publicTestimony.section.supportPill}`,
        );
    });

    it("renders PublicTestimonySection when public_testimony_counts is present on usePage().props", () => {
        mockPageProps = {
            ...mockPageProps,
            public_testimony_counts: {
                total: 5,
                support: 4,
                oppose: 1,
                neutral: 0,
            },
        };

        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        const section = screen.getByTestId("public-testimony-section");
        expect(section).toBeInTheDocument();
        expect(screen.getByText(PARITY_COPY.publicTestimony.section.subtitle(5))).toBeInTheDocument();
    });

    // @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Presenting public testimony on bill pages#Signed-out readers receive no public testimony]]
    it("renders no public testimony section for the signed-out payload, where the server nils counts and letters", () => {
        mockPageProps = {
            ...mockPageProps,
            user: null,
            public_testimony_counts: null,
            public_testimony_letters: null,
        };

        render(<BillContent bill={BASE_BILL} organizations={[]} />);

        expect(screen.queryByTestId("public-testimony-section")).toBeNull();
        expect(screen.queryByText(PARITY_COPY.publicTestimony.section.heading)).toBeNull();
    });
});
