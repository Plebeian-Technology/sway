import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

const patchMock = vi.fn<(...args: any[]) => void>();
const pageMock = vi.fn<() => any>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => pageMock(),
    router: {
        patch: (...args: unknown[]) => patchMock(...args),
    },
    Link: ({ href, children, ...rest }: { href: string; children: React.ReactNode }) => (
        <a href={href} {...rest}>
            {children}
        </a>
    ),
}));

import ReassignmentBanner from "app/frontend/components/legislators/ReassignmentBanner";
import type { sway } from "sway";

afterEach(() => {
    cleanup();
    vi.clearAllMocks();
});

const sampleDistrict: sway.IDistrict = {
    id: 46,
    name: "District 46",
    number: 46,
    region_code: "MD",
};

const sampleOldDistrict: sway.IDistrict = {
    id: 43,
    name: "District 43",
    number: 43,
    region_code: "MD",
};

const sampleLegislator: sway.ILegislator = {
    id: 101,
    title: "Rep.",
    external_id: "ext-101",
    link: "https://example.com/jane",
    email: "jane@example.com",
    phone: "555-0101",
    first_name: "Jane",
    last_name: "Smith",
    full_name: "Jane Smith",
    party: "D",
    active: true,
    sway_locale_id: 1,
    district: sampleDistrict,
};

const sampleOldLegislator: sway.ILegislator = {
    id: 102,
    title: "Rep.",
    external_id: "ext-102",
    link: "https://example.com/bob",
    email: "bob@example.com",
    phone: "555-0102",
    first_name: "Bob",
    last_name: "Jones",
    full_name: "Bob Jones",
    party: "R",
    active: false,
    sway_locale_id: 1,
    district: sampleOldDistrict,
};

describe("ReassignmentBanner", () => {
    it("renders nothing when there are no notifications", () => {
        pageMock.mockReturnValue({
            props: {
                reassignment_notifications: [],
            },
        });

        const { container } = render(<ReassignmentBanner />);
        expect(container.firstChild).toBeNull();
    });

    it("renders district_changed transition correctly with profile link", () => {
        pageMock.mockReturnValue({
            props: {
                reassignment_notifications: [
                    {
                        id: 1,
                        reassignment_type: "district_changed",
                        district: sampleDistrict,
                        previous_district: sampleOldDistrict,
                        legislator: sampleLegislator,
                        previous_legislator: sampleOldLegislator,
                        created_at: "2026-09-10T12:00:00Z",
                    },
                ],
            },
        });

        render(<ReassignmentBanner />);

        const banner = screen.getByTestId("reassignment-banner");
        expect(banner).toBeInTheDocument();
        expect(banner).toHaveAttribute("aria-live", "polite");
        expect(banner).toHaveAttribute("aria-atomic", "true");

        const text = screen.getByTestId("reassignment-banner-text");
        expect(text).toHaveTextContent("Your voting district has changed to District 46.");
        expect(text).toHaveTextContent("Jane Smith");

        const link = screen.getByTestId("reassignment-banner-link");
        expect(link).toHaveAttribute("href", "/legislators/101");

        const dismissBtn = screen.getByTestId("reassignment-banner-dismiss");
        expect(dismissBtn).toHaveClass("min-h-11");
    });

    it("renders successor_seeded transition correctly", () => {
        pageMock.mockReturnValue({
            props: {
                reassignment_notifications: [
                    {
                        id: 2,
                        reassignment_type: "successor_seeded",
                        district: sampleDistrict,
                        previous_district: sampleDistrict,
                        legislator: sampleLegislator,
                        previous_legislator: sampleOldLegislator,
                        created_at: "2026-09-10T12:00:00Z",
                    },
                ],
            },
        });

        render(<ReassignmentBanner />);

        const text = screen.getByTestId("reassignment-banner-text");
        expect(text).toHaveTextContent("Jane Smith has succeeded Bob Jones as your representative for District 46.");
    });

    it("renders vacant_seat notice without legislator profile link", () => {
        pageMock.mockReturnValue({
            props: {
                reassignment_notifications: [
                    {
                        id: 3,
                        reassignment_type: "vacant_seat",
                        district: sampleDistrict,
                        legislator: null,
                        previous_legislator: sampleOldLegislator,
                        created_at: "2026-09-10T12:00:00Z",
                    },
                ],
            },
        });

        render(<ReassignmentBanner />);

        const text = screen.getByTestId("reassignment-banner-text");
        expect(text).toHaveTextContent("Bob Jones no longer represents District 46 and the seat is currently vacant.");
        expect(screen.queryByTestId("reassignment-banner-link")).toBeNull();
    });

    it("renders vacancy_filled transition correctly", () => {
        pageMock.mockReturnValue({
            props: {
                reassignment_notifications: [
                    {
                        id: 4,
                        reassignment_type: "vacancy_filled",
                        district: sampleDistrict,
                        legislator: sampleLegislator,
                        previous_legislator: null,
                        created_at: "2026-09-10T12:00:00Z",
                    },
                ],
            },
        });

        render(<ReassignmentBanner />);

        const text = screen.getByTestId("reassignment-banner-text");
        expect(text).toHaveTextContent("Jane Smith has been seated as your new representative for District 46.");
    });

    it("optimistically dismisses banner on Dismiss click and patches endpoint", () => {
        pageMock.mockReturnValue({
            props: {
                reassignment_notifications: [
                    {
                        id: 42,
                        reassignment_type: "successor_seeded",
                        district: sampleDistrict,
                        legislator: sampleLegislator,
                        previous_legislator: sampleOldLegislator,
                        created_at: "2026-09-10T12:00:00Z",
                    },
                ],
            },
        });

        render(<ReassignmentBanner />);

        const dismissBtn = screen.getByTestId("reassignment-banner-dismiss");
        fireEvent.click(dismissBtn);

        expect(patchMock).toHaveBeenCalledTimes(1);
        expect(patchMock).toHaveBeenCalledWith(
            "/reassignment_notifications/42/dismiss",
            {},
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );

        // Optimistically unmounted
        expect(screen.queryByTestId("reassignment-banner")).toBeNull();
    });
});
