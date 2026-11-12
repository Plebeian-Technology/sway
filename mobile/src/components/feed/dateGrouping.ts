import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import type { IFeedItem, TFeedItemKind } from "./types";

export interface IFeedDateGroup {
    heading: string;
    items: IFeedItem[];
}

interface ICalendarParts {
    year: number;
    month: number;
    day: number;
}

// @lat: [[legislator-botm-record#Release dates are read in UTC]]
export const isUtcDateOnlyKind = (kind: TFeedItemKind): boolean =>
    kind === "bill_of_the_month_released" || kind === "legislative_term_began";

const getCalendarParts = (date: Date, useUtc: boolean): ICalendarParts =>
    useUtc
        ? {
              year: date.getUTCFullYear(),
              month: date.getUTCMonth(),
              day: date.getUTCDate(),
          }
        : {
              year: date.getFullYear(),
              month: date.getMonth(),
              day: date.getDate(),
          };

const dayNumber = (parts: ICalendarParts): number => Date.UTC(parts.year, parts.month, parts.day) / 86_400_000;

export const getDateGroupHeading = (occurredAt: string, kind: TFeedItemKind, now: Date = new Date()): string => {
    const date = new Date(occurredAt);
    const useUtc = isUtcDateOnlyKind(kind);
    const itemParts = getCalendarParts(date, useUtc);
    const todayParts = getCalendarParts(now, useUtc);
    const diffDays = dayNumber(todayParts) - dayNumber(itemParts);

    if (diffDays === 0) {
        return PARITY_COPY.feed.dateHeadings.today;
    }
    if (diffDays === 1) {
        return PARITY_COPY.feed.dateHeadings.yesterday;
    }
    if (itemParts.year === todayParts.year && itemParts.month === todayParts.month) {
        return PARITY_COPY.feed.dateHeadings.earlierThisMonth;
    }

    return date.toLocaleDateString("en-US", {
        month: "long",
        year: "numeric",
        ...(useUtc ? { timeZone: "UTC" } : {}),
    });
};

export const groupFeedItemsByDate = (items: IFeedItem[], now: Date = new Date()): IFeedDateGroup[] => {
    const groups: IFeedDateGroup[] = [];

    for (const item of items) {
        const heading = getDateGroupHeading(item.occurred_at, item.kind, now);
        const lastGroup = groups[groups.length - 1];
        if (lastGroup && lastGroup.heading === heading) {
            lastGroup.items.push(item);
        } else {
            groups.push({ heading, items: [item] });
        }
    }

    return groups;
};

export const formatItemTimestamp = (occurredAt: string, kind: TFeedItemKind, now: Date = new Date()): string => {
    const date = new Date(occurredAt);
    const useUtc = isUtcDateOnlyKind(kind);
    const itemParts = getCalendarParts(date, useUtc);
    const todayParts = getCalendarParts(now, useUtc);
    const diffDays = dayNumber(todayParts) - dayNumber(itemParts);

    if (!useUtc && (diffDays === 0 || diffDays === 1)) {
        return date
            .toLocaleTimeString("en-US", {
                hour: "numeric",
                minute: "2-digit",
            })
            .toLowerCase();
    }

    if (itemParts.year === todayParts.year) {
        return date.toLocaleDateString("en-US", {
            month: "short",
            day: "numeric",
            ...(useUtc ? { timeZone: "UTC" } : {}),
        });
    }

    return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        ...(useUtc ? { timeZone: "UTC" } : {}),
    });
};

// @lat: [[legislator-botm-record#Release dates are read in UTC]]
export const formatReleaseMonthUtc = (occurredAt: string): string =>
    new Date(occurredAt).toLocaleDateString("en-US", {
        month: "long",
        timeZone: "UTC",
    });
