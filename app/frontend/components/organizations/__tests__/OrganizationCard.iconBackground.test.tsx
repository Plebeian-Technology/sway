import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

vi.mock("@inertiajs/react", async (importActual) => ({
    ...(await importActual<typeof import("@inertiajs/react")>()),
    Link: ({ href, children }: React.PropsWithChildren<{ href: string }>) => <a href={href}>{children}</a>,
}));

import OrganizationCard from "app/frontend/components/organizations/OrganizationCard";

const organization = (icon_url: string | null) =>
    ({ id: 11, name: "Bikemore", follower_count: 0, icon_url }) as unknown as sway.IPublicOrganization;

describe("OrganizationCard icon tile", () => {
    afterEach(cleanup);

    it("draws a logo without the gray tile behind it", () => {
        render(<OrganizationCard organization={organization("https://example.test/bikemore.png")} />);

        const tile = screen.getByAltText("Bikemore logo").parentElement;
        expect(tile?.className).not.toContain("bg-surface-2");
    });

    it("keeps the gray tile behind the placeholder icon when there is no logo", () => {
        const { container } = render(<OrganizationCard organization={organization(null)} />);

        const tile = container.querySelector("svg")?.parentElement;
        expect(tile?.className).toContain("bg-surface-2");
    });
});
