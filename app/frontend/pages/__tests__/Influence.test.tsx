import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const usePollMock =
    vi.fn<(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>(() => false);

vi.mock("@inertiajs/react", () => ({
    // Named `function usePoll` so the rules-of-hooks linter treats the mock as a hook.
    usePoll: function usePoll(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) {
        usePollMock(interval, options, pollOptions);
    },
}));

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({
    useScoreSubscription: (only: string[]) => scoreSubscriptionMock(only),
}));

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [
        { id: 1, name: "baltimore-maryland-united_states" },
        vi.fn<(swayLocaleId: number) => void>(),
        undefined,
    ],
    useSwayLocales: () => ({ options: [] }),
}));

import Influence from "app/frontend/pages/Influence";

afterEach(() => {
    cleanup();
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
});

const influence = {
    count_bills_voted_on: 3,
    count_invites_redeemed: 1,
    count_bills_shared: 2,
    total_sway: 6,
} as unknown as sway.IInfluence;

describe("Influence — poll + score-subscription refresh contract", () => {
    it("polls every 15s with only:[influence] and subscribes on the same tuple", () => {
        render(<Influence user={{} as sway.IUser} influence={influence} />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(15000, { only: ["influence"] }, { background: "pause" });
        expect(scoreSubscriptionMock).toHaveBeenCalledWith(["influence"]);
        expect(usePollMock.mock.calls[0][1].only).toBe(scoreSubscriptionMock.mock.calls[0][0]);
    });

    it("does not list sway_locale, which a background refresh would rebuild the picker from", () => {
        render(<Influence user={{} as sway.IUser} influence={influence} />);

        expect(usePollMock.mock.calls[0][1].only).not.toContain("sway_locale");
    });

    it("renders the 'Your Sway' page heading", () => {
        const { getByRole } = render(<Influence user={{} as sway.IUser} influence={influence} />);

        expect(getByRole("heading", { level: 1, name: "Your Sway" })).toBeDefined();
    });
});
