// @lat: [[legislators-controller-design#Why LegislatorsLocaleGuard.test.tsx is its own file]]

import { cleanup, render } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

vi.mock("@inertiajs/react", () => ({
    usePoll: vi.fn<(callback: () => void, interval: number) => void>(),
    router: {
        reload: vi.fn<(...args: unknown[]) => void>(),
        post: vi.fn<(...args: unknown[]) => void>(),
        on: vi.fn<(type: string, callback: unknown) => () => void>(() => vi.fn<() => void>()),
    },
    Link: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
vi.mock("app/frontend/hooks/useScoreSubscription", () => ({ useScoreSubscription: vi.fn<() => void>() }));
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [undefined, vi.fn<(locale: unknown) => void>()],
    useSwayLocales: () => ({ options: [] }),
}));
vi.mock("app/frontend/components/legislators/LegislatorCard", () => ({
    default: () => <div data-testid="legislator-card" />,
}));

import Legislators from "app/frontend/pages/Legislators";

afterEach(() => cleanup());

describe("Legislators — nil-locale guard", () => {
    it("renders without throwing when no locale is set", () => {
        expect(() =>
            render(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            ),
        ).not.toThrow();
    });
});
