import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: { user: null, pending_vote: null, errors: {}, sway_locale: {} } }),
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
    useForm: function useForm(initial: Record<string, unknown>) {
        return {
            data: initial ?? {},
            setData: vi.fn<() => void>(),
            post: vi.fn<() => void>(),
            processing: false,
            transform: vi.fn<() => void>(),
            reset: vi.fn<() => void>(),
            errors: {},
        };
    },
    usePoll: vi.fn<() => void>(),
    router: { reload: vi.fn<() => void>() },
}));
vi.mock("app/frontend/hooks/useLocales", () => ({
    useLocaleName: () => "baltimore",
    useLocale: () => [{ id: 1, name: "baltimore" }, vi.fn<() => void>(), null],
    useLocales: () => ({ options: [{ id: 1, name: "baltimore" }] }),
}));
vi.mock("app/frontend/hooks/useScoreSubscription", () => ({ useScoreSubscription: () => false }));
vi.mock("app/frontend/hooks/useActionCableReconnect", () => ({ useActionCableReconnect: vi.fn<() => void>() }));
vi.mock("app/frontend/hooks/usePullToRefresh", () => ({ usePullToRefresh: vi.fn<() => void>() }));
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<() => Promise<boolean>>(() => Promise.resolve(true)),
}));
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({
    useOffline: () => ({ isOnline: true, assertBanner: vi.fn<() => void>() }),
}));
vi.mock("app/frontend/components/bill/EmailLegislatorsModal", () => ({ default: () => null }));
vi.mock("app/frontend/components/bill/charts/BillChartsPanel", () => ({ default: () => null }));
vi.mock("app/frontend/components/bill/charts/BillAffinityPanel", () => ({ default: () => null }));
vi.mock("app/frontend/components/bill/layouts/LazyBillSummaryMarkdown", () => ({
    default: ({ summary }: { summary: string }) => <p>{summary}</p>,
}));

import BillContent from "app/frontend/components/bill/BillContent";
import BallotBillLayout from "app/frontend/components/bill/layouts/BallotBillLayout";
import BannerBillLayout from "app/frontend/components/bill/layouts/BannerBillLayout";
import CornerstoreBillLayout from "app/frontend/components/bill/layouts/CornerstoreBillLayout";
import MonochromeBillLayout from "app/frontend/components/bill/layouts/MonochromeBillLayout";
import ServiceManualBillLayout from "app/frontend/components/bill/layouts/ServiceManualBillLayout";
import SwissGridBillLayout from "app/frontend/components/bill/layouts/SwissGridBillLayout";

const BILL = { id: 101, external_id: "26-0042", title: "Tree Canopy Act", summary: "Summary." } as sway.IBill;
const SPONSOR = { id: 12, full_name: "Odette Ramos" } as sway.ILegislator;

const POSITIONS = [
    {
        id: 501,
        bill_id: 101,
        support: Support.For,
        summary: "Improves water quality.",
        summary_ai_unreviewed: false,
        source_kind: "organization",
        source_url: null,
        organization: { id: 1, name: "Bay Foundation", sway_locale_id: 1 },
    },
    {
        id: 502,
        bill_id: 101,
        support: Support.Against,
        summary: "Raises compliance costs.",
        summary_ai_unreviewed: false,
        source_kind: "news_article",
        source_url: "https://news.example/chamber",
        organization: { id: 2, name: "Chamber of Commerce", sway_locale_id: 1 },
    },
] as sway.IBillOrganizationPosition[];

type Renderer = (organizations: sway.IBillOrganizationPosition[]) => React.ReactElement;

const LAYOUTS: [string, Renderer][] = [
    ["BillContent", (organizations) => <BillContent bill={BILL} organizations={organizations} />],
    ...(
        [
            ["BallotBillLayout", BallotBillLayout],
            ["BannerBillLayout", BannerBillLayout],
            ["CornerstoreBillLayout", CornerstoreBillLayout],
            ["MonochromeBillLayout", MonochromeBillLayout],
            ["ServiceManualBillLayout", ServiceManualBillLayout],
            ["SwissGridBillLayout", SwissGridBillLayout],
        ] as const
    ).map(([name, Layout]): [string, Renderer] => [
        name,
        (organizations) => (
            <Layout bill={BILL} sponsor={SPONSOR} organizations={organizations} isAwaitingScoreUpdate={false} />
        ),
    ]),
];

beforeAll(async () => {
    await import("app/frontend/components/bill/BillSummaryMarkdown");
});

afterEach(cleanup);

describe.each(LAYOUTS)("%s organization positions", (_name, renderLayout) => {
    it("shows the notice once and tags each position by who wrote it", () => {
        render(renderLayout(POSITIONS));

        expect(screen.getAllByText(PARITY_COPY.orgs.listNotice)).toHaveLength(1);
        const tags = screen.getAllByTestId("org-position-source-tag").map((tag) => tag.textContent);
        expect(tags.toSorted()).toEqual(["Compiled by Sway", "Posted by Bay Foundation"]);
    });

    it("links a position to its source", () => {
        render(renderLayout(POSITIONS));

        const link = screen.getByRole("link", { name: new RegExp(PARITY_COPY.orgs.sourceNewsArticle) });
        expect(link.getAttribute("href")).toBe("https://news.example/chamber");
    });

    it("shows no notice when the bill has no organization positions", () => {
        render(renderLayout([]));

        expect(screen.queryByText(PARITY_COPY.orgs.listNotice)).toBeNull();
    });
});
