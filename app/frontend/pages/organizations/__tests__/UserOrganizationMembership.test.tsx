import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { routerVisit, useMembershipMock, usePageMock } = vi.hoisted(() => ({
    routerVisit: vi.fn<(url: string, options?: unknown) => void>(),
    useMembershipMock: vi.fn<
        () => {
            id: number;
            role: string;
            organization: { id: number; name: string };
            positions: unknown[];
            pending_changes: unknown[];
        }
    >(),
    usePageMock: vi.fn<() => { props: Record<string, unknown> }>(),
}));

vi.mock("@inertiajs/react", () => ({
    router: { visit: routerVisit },
    usePage: usePageMock,
}));

vi.mock("app/frontend/hooks/users/useUserOrganizationMembership", () => ({
    useUserOrganizationMembership: useMembershipMock,
}));

vi.mock("app/frontend/components/organizations/MembershipHeader", () => ({
    default: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
}));
vi.mock("app/frontend/components/organizations/MembersList", () => ({
    default: () => <div>Members panel</div>,
}));
vi.mock("app/frontend/components/organizations/PendingChangesList", () => ({
    default: () => <div>Pending changes panel</div>,
}));
vi.mock("app/frontend/components/organizations/PositionsList", () => ({
    default: () => <div>Positions panel</div>,
}));

import UserOrganizationMembership from "app/frontend/pages/organizations/UserOrganizationMembership";

const MEMBERSHIP = {
    id: 12,
    role: "standard",
    organization: { id: 34, name: "Neighborhood Group" },
    positions: [],
    pending_changes: [],
};

beforeEach(() => {
    useMembershipMock.mockReturnValue(MEMBERSHIP);
    usePageMock.mockReturnValue({ props: {} });
});

afterEach(() => {
    cleanup();
    routerVisit.mockReset();
    useMembershipMock.mockReset();
    usePageMock.mockReset();
});

// @lat: [[organizations-memberships-controller-notes#The membership detail page]]
describe("UserOrganizationMembership tabs", () => {
    it("defaults to positions and keeps tabs visible for a standard member", () => {
        render(<UserOrganizationMembership />);

        expect(screen.getByRole("tab", { name: "Positions" })).toHaveAttribute("aria-selected", "true");
        expect(screen.getByRole("tab", { name: "Pending Changes" })).toHaveAttribute("aria-selected", "false");
        expect(screen.queryByRole("tab", { name: "Members" })).not.toBeInTheDocument();
    });

    it("maps the historical approvals value to the pending changes tab", () => {
        usePageMock.mockReturnValue({ props: { tab: "approvals" } });

        render(<UserOrganizationMembership />);

        expect(screen.getByRole("tab", { name: "Pending Changes" })).toHaveAttribute("aria-selected", "true");
    });

    it("writes the canonical organization tab name when the selection changes", async () => {
        render(<UserOrganizationMembership />);

        await userEvent.setup().click(screen.getByRole("tab", { name: "Pending Changes" }));

        expect(routerVisit).toHaveBeenCalledWith(
            "/organizations/34/memberships/12?org_tab=changes",
            expect.objectContaining({ method: "get", preserveState: true, preserveScroll: true, replace: true }),
        );
    });
});
