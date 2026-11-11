import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    Link: ({ href, children, ...props }: { href: string; children: ReactNode }) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocaleSlug: () => "baltimore-maryland-united_states",
    useSwayLocale: () => [
        { id: 1, name: "baltimore-maryland-united_states", city: "Baltimore", region_name: "Maryland", country: "US" },
        () => undefined,
    ],
}));

vi.mock("app/frontend/components/ui/card", () => ({
    Card: ({ children, ...props }: { children: ReactNode }) => <div {...props}>{children}</div>,
    CardHeader: ({ children, ...props }: { children: ReactNode }) => <div {...props}>{children}</div>,
    CardTitle: ({ children, ...props }: { children: ReactNode }) => <div {...props}>{children}</div>,
    CardContent: ({ children, ...props }: { children: ReactNode }) => <div {...props}>{children}</div>,
}));

import LegislatorCard from "app/frontend/components/legislators/LegislatorCard";

describe("LegislatorCard", () => {
    it("renders the representative image when photo_url is present", () => {
        render(
            <LegislatorCard
                legislator={
                    {
                        id: 42,
                        full_name: "Jane Doe",
                        external_id: "abc-123",
                        title: "Delegate",
                        party: "Independent",
                        photo_url: "https://example.com/jane.jpg",
                        user_legislator_score: null,
                    } as any
                }
            />,
        );

        expect(screen.getByRole("img", { name: "Jane Doe avatar" })).toHaveAttribute(
            "src",
            "https://example.com/jane.jpg",
        );
        expect(screen.getByRole("link", { name: /view representative/i })).toHaveAttribute("href", "/legislators/42");
    });

    it("falls back to the default avatar when photo_url is missing", () => {
        render(
            <LegislatorCard
                legislator={
                    {
                        id: 99,
                        full_name: "John Smith",
                        external_id: "def-456",
                        title: "Senator",
                        party: "Democrat",
                        photo_url: "",
                        user_legislator_score: null,
                    } as any
                }
            />,
        );

        expect(screen.getByRole("img", { name: "John Smith avatar" })).toHaveAttribute("src", "/images/politician.svg");
    });

    it("renders the representative link and voter agreement toggle in the same action cluster", () => {
        render(
            <LegislatorCard
                legislator={
                    {
                        id: 42,
                        full_name: "Jane Doe",
                        external_id: "abc-123",
                        title: "Delegate",
                        party: "Independent",
                        photo_url: "",
                        user_legislator_score: {
                            count_agreed: 4,
                            count_disagreed: 1,
                            count_no_legislator_vote: 2,
                        },
                    } as any
                }
            />,
        );

        expect(screen.getByRole("link", { name: /view representative/i })).toBeInTheDocument();
        expect(screen.getByRole("button", { name: /show voter agreement/i })).toBeInTheDocument();
    });

    it("warms the representative link on mousedown rather than on hover", () => {
        render(
            <LegislatorCard
                legislator={
                    {
                        id: 42,
                        full_name: "Jane Doe",
                        external_id: "abc-123",
                        title: "Delegate",
                        party: "Independent",
                        photo_url: "",
                        user_legislator_score: null,
                    } as any
                }
            />,
        );

        expect(screen.getByRole("link", { name: /view representative/i })).toHaveAttribute("prefetch", "click");
    });
});
