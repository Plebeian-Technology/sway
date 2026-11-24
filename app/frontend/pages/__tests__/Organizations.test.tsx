import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const getSwayLocaleMock = vi.fn<(swayLocaleId: number) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: { user: null } }),
    // Named `function usePoll` so the rules-of-hooks linter treats the mock as a hook.
    usePoll: function usePoll() {},
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

afterEach(() => {
    cleanup();
    getSwayLocaleMock.mockClear();
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
