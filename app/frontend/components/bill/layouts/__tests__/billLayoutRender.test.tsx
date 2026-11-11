import { cleanup, render, screen, waitFor } from "@testing-library/react";
import * as React from "react";
import { Suspense } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

// @lat: [[client-caches-and-identity#Bill refresh feedback]]

vi.mock("@inertiajs/react", () => ({
    router: {
        on: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
    },
    usePage: () => ({
        props: {
            user: null,
            pending_vote: null,
            errors: {},
        },
    }),
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
    useForm: function useForm(initial: Record<string, unknown>) {
        const [data, setDataState] = React.useState<Record<string, unknown>>(initial ?? {});
        const setData = (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value }));
        return {
            data,
            setData,
            post: vi.fn<() => void>(),
            processing: false,
            transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
            reset: vi.fn<() => void>(),
            errors: {},
        };
    },
}));

vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<(message: string) => Promise<boolean>>(),
}));
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({
    useOffline: () => ({ isOnline: true, assertBanner: vi.fn<() => void>() }),
}));
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocaleSlug: () => "baltimore",
    useSwayLocale: () => [null, vi.fn<() => void>()],
    useSwayLocales: () => ({ options: [] }),
}));
vi.mock("app/frontend/components/bill/EmailLegislatorsModal", () => ({
    default: () => <div data-testid="email-legislators" />,
}));

import { billLayoutFor } from "app/frontend/components/bill/layouts/index";
import DefaultBillLayout from "app/frontend/components/bill/layouts/DefaultBillLayout";
import { THEMES, type ThemeId } from "app/frontend/styles/themes";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";

// A realistic bill: its long legal title carries Maryland's "FOR the purpose
// of" boilerplate, which the layouts are supposed to push out of the headline.
const BILL = {
    id: 7,
    external_id: "25-0003",
    title: "Historic Preservation — Conservation Districts FOR the purpose of establishing Conservation Districts; providing a study, proposal, and review process; defining certain terms; and providing for a special effective date.",
    summary: "Lets Baltimore create Conservation Districts.",
    chamber: "council",
    categories: ["Environment", "Housing"],
    legislator_id: 3,
} as unknown as sway.IBill;

const SPONSOR = { id: 3, full_name: "Zeke Cohen" } as sway.ILegislator;

const PROPS: BillLayoutProps = {
    bill: BILL,
    sponsor: SPONSOR,
    organizations: [],
    isAwaitingScoreUpdate: false,
};

// Every theme in the manifest, so a newly registered theme is covered the
// moment it is added rather than whenever someone remembers to list it here.
const ALL_THEMES: ThemeId[] = THEMES.map((t) => t.id);

// Resolve every lazy() chunk once, before any example is on the clock.
// @lat: [[client-caches-and-identity#Bill refresh feedback]]
await Promise.all([
    import("app/frontend/components/bill/layouts/BannerBillLayout"),
    import("app/frontend/components/bill/layouts/BallotBillLayout"),
    import("app/frontend/components/bill/layouts/CornerstoreBillLayout"),
    import("app/frontend/components/bill/layouts/MonochromeBillLayout"),
    import("app/frontend/components/bill/layouts/ServiceManualBillLayout"),
    import("app/frontend/components/bill/layouts/SwissGridBillLayout"),
]);

describe.each(ALL_THEMES)("bill layout for the %s theme", (themeId) => {
    beforeEach(() => vi.clearAllMocks());
    afterEach(cleanup);

    const renderLayout = (overrideProps: Partial<typeof PROPS> = {}) => {
        const Layout = billLayoutFor(themeId);
        return render(
            <Suspense fallback={<div data-testid="loading" />}>
                <Layout {...PROPS} {...overrideProps} />
            </Suspense>,
        );
    };

    it("mounts and renders the bill without throwing", async () => {
        renderLayout();

        // Lazily loaded layouts arrive a moment later; the default is there
        // straight away.
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());
        // getAllBy, because a layout may fairly show the bill code more than
        // once: Corner Store has it as a chip and again in the document line.
        expect(screen.getAllByText(/25-0003/).length).toBeGreaterThan(0);
    });

    // @lat: [[client-caches-and-identity#Bill refresh feedback]]
    it("keeps the legislature's own wording out of the heading", async () => {
        renderLayout();
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        const heading = screen.getByTestId("bill-title");
        expect(heading.textContent).toContain("Historic Preservation");
        expect(heading.textContent).not.toContain("FOR the purpose of");
    });

    // @lat: [[client-caches-and-identity#Bill refresh feedback]]
    it("still shows the stored title in full, under a label", async () => {
        renderLayout();
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(document.body.textContent).toContain("FOR the purpose of establishing Conservation Districts");
    });

    it("offers both vote choices as real, operable buttons", async () => {
        renderLayout();
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        await waitFor(() => {
            expect(screen.getByRole("button", { name: /Support this legislation/ })).toBeEnabled();
        });
        expect(screen.getByRole("button", { name: /Oppose this legislation/ })).toBeEnabled();
    });

    it("renders approved related articles outside summary and testimony when present", async () => {
        const billWithArticles = {
            ...BILL,
            related_articles: [
                {
                    id: 99,
                    title: "City Hall Advances Historic Preservation Reform",
                    url: "https://baltimorebanner.com/preservation-2026",
                    outlet_name: "The Baltimore Banner",
                    published_at: "2026-03-01T10:00:00Z",
                    article_kind: "reporting",
                    match_kind: "direct",
                } as sway.INewsArticle,
            ],
        };
        renderLayout({ bill: billWithArticles });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        const link = screen.getByRole("link", { name: /City Hall Advances Historic Preservation Reform/i });
        expect(link).toBeInTheDocument();
        expect(link).toHaveAttribute("href", "https://baltimorebanner.com/preservation-2026");
        expect(screen.getByTestId("related-news-articles")).toBeInTheDocument();
    });

    it("renders zero related news DOM elements when related_articles is empty or omitted", async () => {
        const billNoArticles = { ...BILL, related_articles: [] };
        renderLayout({ bill: billNoArticles });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.queryByTestId("related-news-articles")).toBeNull();
    });

    it("renders attributed news testimony across all themes when present", async () => {
        const billWithTestimonies = {
            ...BILL,
            news_testimonies: [
                {
                    id: 101,
                    author_name: "Dr. Alistair Finch",
                    outlet_name: "Maryland Matters",
                    url: "https://marylandmatters.org/commentary/districts",
                    stance: "support",
                    argument: "Conservation districts safeguard vernacular neighborhood architecture.",
                } as sway.INewsArticleTestimony,
                {
                    id: 102,
                    author_name: "Tara Sterling",
                    outlet_name: "Baltimore Brew",
                    url: "https://baltimorebrew.com/commentary/conservation-critique",
                    stance: "oppose",
                    argument: "Strict historic designations risk exacerbating neighborhood gentrification.",
                } as sway.INewsArticleTestimony,
            ],
        };

        renderLayout({ bill: billWithTestimonies });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.getByText(/Dr\. Alistair Finch/)).toBeInTheDocument();
        expect(screen.getByText(/Tara Sterling/)).toBeInTheDocument();
        expect(screen.getByText(/Conservation districts safeguard/)).toBeInTheDocument();
        expect(screen.getByText(/Strict historic designations risk/)).toBeInTheDocument();
        expect(screen.getAllByTestId("news-article-testimony").length).toBeGreaterThanOrEqual(2);
    });

    it("renders zero news testimony DOM elements across all themes when news_testimonies is empty", async () => {
        const billNoTestimony = { ...BILL, news_testimonies: [] };
        renderLayout({ bill: billNoTestimony });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.queryByTestId("news-article-testimony")).toBeNull();
    });

    it("renders the share bill button across all themes when user_vote is undefined", async () => {
        renderLayout({ user_vote: undefined });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
    });

    it("renders the share bill button across all themes when user_vote is present", async () => {
        const userVote: sway.IUserVote = {
            id: 1,
            bill_id: BILL.id,
            user_id: 1,
            position: "support",
        } as unknown as sway.IUserVote;

        renderLayout({ user_vote: userVote });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
    });

    it("renders the share bill button and suppresses email modal when bill is inactive and user_vote is present across all themes", async () => {
        const inactiveBill = { ...BILL, active: false };
        const userVote: sway.IUserVote = {
            id: 1,
            bill_id: BILL.id,
            user_id: 1,
            position: "support",
        } as unknown as sway.IUserVote;

        renderLayout({ bill: inactiveBill, user_vote: userVote });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
        expect(screen.queryByTestId("email-legislators")).toBeNull();
    });

    it("renders both share bill button and email modal when bill is active and user_vote is present across all themes", async () => {
        const activeBill = { ...BILL, active: true };
        const userVote: sway.IUserVote = {
            id: 1,
            bill_id: BILL.id,
            user_id: 1,
            position: "support",
        } as unknown as sway.IUserVote;

        renderLayout({ bill: activeBill, user_vote: userVote });
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
        expect(screen.getByTestId("email-legislators")).toBeInTheDocument();
    });
});

describe("the default bill layout's markup", () => {
    afterEach(cleanup);

    // @lat: [[user-vote-submission#Themed web vote controls#Where the default control sits]]
    it("seats the ballot inside the hero, after the title and ahead of the score panel", () => {
        const { container } = render(<DefaultBillLayout {...PROPS} />);

        const root = container.firstElementChild as HTMLElement;
        const hero = screen.getByTestId("bill-hero");
        const title = screen.getByTestId("bill-title");
        const ballot = screen.getByTestId("bill-ballot");
        const score = screen.getByTestId("score-panel");

        expect(root.getAttribute("data-page-width")).toBeNull();
        expect(hero.contains(title)).toBe(true);
        expect(hero.contains(ballot)).toBe(true);
        expect(title.compareDocumentPosition(ballot) & Node.DOCUMENT_POSITION_FOLLOWING).not.toBe(0);
        expect(ballot.compareDocumentPosition(score) & Node.DOCUMENT_POSITION_FOLLOWING).not.toBe(0);
        expect(hero.contains(score)).toBe(false);
    });

    it("keeps the legislature's own wording out of the hero, so the ballot is not pushed under it", () => {
        render(<DefaultBillLayout {...PROPS} />);

        expect(screen.getByTestId("bill-hero").textContent).not.toContain("FOR the purpose of");
        expect(document.body.textContent).toContain("FOR the purpose of establishing Conservation Districts");
    });
});

describe("the cornerstore bill layout's kicker", () => {
    afterEach(cleanup);

    it("renders 'On the floor' and not 'This week on the floor'", async () => {
        const Layout = billLayoutFor("cornerstore");
        render(
            <Suspense fallback={<div data-testid="loading" />}>
                <Layout {...PROPS} />
            </Suspense>,
        );
        await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

        expect(screen.getByText("On the floor")).toBeTruthy();
        expect(screen.queryByText("This week on the floor")).toBeNull();
    });
});
