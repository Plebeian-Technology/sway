import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { formatItemTimestamp, groupFeedItemsByDate } from "app/frontend/components/feed/dateGrouping";
import type { IFeedItem, TFeedItemKind } from "app/frontend/components/feed/types";

const NOW = new Date("2026-11-12T18:00:00Z");

const makeItem = (key: string, kind: TFeedItemKind, occurredAt: string): IFeedItem => ({
    key,
    kind,
    occurred_at: occurredAt,
    sway_locale: null,
    bill: null,
    legislator: null,
    legislators: [],
    organization: null,
    user_support: null,
    legislator_support: null,
    agreement: null,
});

describe("feed date grouping in America/New_York", () => {
    let originalTz: string | undefined;

    beforeEach(() => {
        originalTz = process.env.TZ;
        process.env.TZ = "America/New_York";
    });

    afterEach(() => {
        process.env.TZ = originalTz;
    });

    it("groups a midnight-UTC vote with a Bill of the Month on the same date and shows a date, not a clock time", () => {
        const vote = makeItem("vote:dated", "legislator_voted", "2026-11-12T00:00:00Z");
        const botm = makeItem("botm:1", "bill_of_the_month_released", "2026-11-12T00:00:00Z");

        const groups = groupFeedItemsByDate([vote, botm], NOW);

        expect(groups).toEqual([{ heading: "Today", items: [vote, botm] }]);
        expect(formatItemTimestamp(vote.occurred_at, vote.kind, NOW)).toEqual("Nov 12");
    });

    it("reads a vote with a real timestamp in local time", () => {
        const vote = makeItem("vote:timed", "legislator_voted", "2026-11-12T03:30:00Z");

        const groups = groupFeedItemsByDate([vote], NOW);

        expect(groups).toEqual([{ heading: "Yesterday", items: [vote] }]);
        expect(formatItemTimestamp(vote.occurred_at, vote.kind, NOW)).toEqual("10:30 pm");
    });
});
