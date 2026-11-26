import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const getSwayLocaleMock = vi.fn<(swayLocaleId: number) => void>();
const routerGetMock = vi.fn<(url: string, data: object, options: { only?: string[] }) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: { user: null } }),
    // Named `function usePoll` so the rules-of-hooks linter treats the mock as a hook.
    usePoll: function usePoll() {},
    router: { get: (url: string, data: object, options: { only?: string[] }) => routerGetMock(url, data, options) },
}));

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ id: 1, name: "baltimore-maryland-united_states" }, getSwayLocaleMock, undefined],
    useSwayLocales: () => ({
        sway_locales: [],
        options: [
            { value: 1, label: "Baltimore" },
            { value: 2, label: "Maryland" },
        ],
    }),
}));

vi.mock("app/frontend/components/organizations/OrganizationCard", () => ({
    default: ({ organization }: { organization: sway.IPublicOrganization }) => (
        <div data-testid="public-organization-card">{organization.name}</div>
    ),
}));

import Organizations from "app/frontend/pages/Organizations";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

afterEach(() => {
    cleanup();
    getSwayLocaleMock.mockClear();
    routerGetMock.mockClear();
    vi.useRealTimers();
    window.history.replaceState({}, "", "/");
});

const appliedFilters = { locale_id: "1", sway_locale_id: "1", org_search: null };

const housingCoalition = {
    id: 10,
    name: "Housing Coalition",
    sway_locale_id: 1,
} as sway.IPublicOrganization;

describe("Organizations — locale picker", () => {
    it("shows the current locale in the picker", () => {
        render(<Organizations organizations={[housingCoalition]} applied_filters={appliedFilters} />);

        const picker = screen.getByLabelText("Locale") as HTMLSelectElement;
        expect(picker.value).toBe("1");
    });

    it("switches locale through the shared locale switch", () => {
        render(<Organizations organizations={[housingCoalition]} applied_filters={appliedFilters} />);

        fireEvent.change(screen.getByLabelText("Locale"), { target: { value: "2" } });

        expect(getSwayLocaleMock).toHaveBeenCalledWith(2);
    });

    it("says no organizations were found for the selected locale when the list is empty", () => {
        render(<Organizations organizations={[]} applied_filters={appliedFilters} />);

        expect(screen.getByTestId("public-organizations-empty").textContent).toBe(
            PARITY_COPY.orgs.noneFound("Baltimore, Maryland, United States"),
        );
    });
});

describe("Organizations — name search", () => {
    const lastNavigation = () => {
        expect(routerGetMock).toHaveBeenCalledTimes(1);
        const [url, , options] = routerGetMock.mock.calls[0];
        return { url, params: new URLSearchParams(url.split("?")[1] ?? ""), options };
    };

    it("starts from the search in the address", () => {
        window.history.replaceState({}, "", "/public/organizations?sway_locale_id=1&org_search=hous");
        render(
            <Organizations
                organizations={[housingCoalition]}
                applied_filters={{ ...appliedFilters, org_search: "hous" }}
            />,
        );

        expect((screen.getByLabelText("Search organizations") as HTMLInputElement).value).toBe("hous");
    });

    it("writes org_search to the address after a pause, keeps the locale and reloads only the list props", () => {
        vi.useFakeTimers();
        window.history.replaceState({}, "", "/public/organizations?sway_locale_id=2");
        render(<Organizations organizations={[housingCoalition]} applied_filters={appliedFilters} />);

        fireEvent.change(screen.getByLabelText("Search organizations"), { target: { value: "hous" } });
        expect(routerGetMock).not.toHaveBeenCalled();
        vi.advanceTimersByTime(400);

        const { params, options } = lastNavigation();
        expect(params.get("org_search")).toBe("hous");
        expect(params.get("sway_locale_id")).toBe("2");
        expect(options.only).toContain("organizations");
        expect(options.only).toContain("applied_filters");
    });

    it("clearing the box removes org_search and keeps the locale", () => {
        vi.useFakeTimers();
        window.history.replaceState({}, "", "/public/organizations?sway_locale_id=2&org_search=hous");
        render(
            <Organizations
                organizations={[housingCoalition]}
                applied_filters={{ ...appliedFilters, org_search: "hous" }}
            />,
        );

        fireEvent.change(screen.getByLabelText("Search organizations"), { target: { value: "" } });
        vi.advanceTimersByTime(400);

        const { url, params } = lastNavigation();
        expect(isQueryParamCleared(params, "org_search")).toBe(true);
        expect(stripClearedQueryParams(url)).toBe("/public/organizations?sway_locale_id=2");
    });

    it("says nothing matched the search instead of the empty-locale message", () => {
        render(<Organizations organizations={[]} applied_filters={{ ...appliedFilters, org_search: "zzz" }} />);

        expect(screen.getByTestId("public-organizations-empty").textContent).toBe('No organizations match "zzz".');
    });
});
