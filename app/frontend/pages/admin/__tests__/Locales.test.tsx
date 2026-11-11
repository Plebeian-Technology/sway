import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

const patch = vi.fn<(url?: string, options?: unknown) => void>();
const transform = vi.fn<(callback: (data: unknown) => unknown) => void>();

vi.mock("@inertiajs/react", () => ({
    useForm: (initial: unknown) => ({
        data: initial,
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        transform,
        patch,
        reset: vi.fn<() => void>(),
        processing: false,
        errors: {},
    }),
}));

import Locales from "app/frontend/pages/admin/Locales";

const emptySample = {
    sample_street: null,
    sample_postal_code: null,
    sample_latitude: null,
    sample_longitude: null,
};

const tiers = [
    {
        key: "city",
        label: "City",
        locales: [
            {
                id: 1,
                label: "Baltimore, Maryland, United States",
                user_count: 3,
                sample_street: "100 N Holliday St",
                sample_postal_code: "21202",
                sample_latitude: 39.29105,
                sample_longitude: -76.61069,
                summarization_instruction: {
                    id: 10,
                    sway_locale_id: 1,
                    news_media_website_urls: ["https://www.thebanner.com/baltimore/", "https://baltimorebrew.com/"],
                    legislative_body_makeup: "A 15-member legislative body.",
                    last_seeded_at: "2026-09-01T00:00:00Z",
                    updated_at: "2026-09-01T00:00:00Z",
                },
                news_sources: [
                    { url: "https://www.thebanner.com/baltimore/", path_policy: "search_hint" as const },
                    { url: "https://baltimorebrew.com/", path_policy: "restrict" as const },
                ],
            },
            {
                id: 2,
                label: "Annapolis, Maryland, United States",
                user_count: 1,
                ...emptySample,
                summarization_instruction: null,
                news_sources: [],
            },
        ],
    },
    {
        key: "state",
        label: "State",
        locales: [
            {
                id: 3,
                label: "Maryland, United States",
                user_count: 4,
                ...emptySample,
                summarization_instruction: null,
                news_sources: [],
            },
        ],
    },
    {
        key: "congress",
        label: "U.S. Congress",
        locales: [
            {
                id: 4,
                label: "U.S. Congress",
                user_count: 4,
                ...emptySample,
                summarization_instruction: null,
                news_sources: [],
            },
        ],
    },
];

afterEach(() => {
    cleanup();
    patch.mockClear();
    transform.mockClear();
});

describe("admin/Locales", () => {
    it("renders each tier with its locale rows and counts", () => {
        render(<Locales tiers={tiers} />);

        expect(screen.getByRole("heading", { level: 1, name: "Locales" })).toBeInTheDocument();
        expect(screen.getByText("City")).toBeInTheDocument();
        expect(screen.getByText("State")).toBeInTheDocument();
        // Tier header + the congress locale row both read "U.S. Congress".
        expect(screen.getAllByText("U.S. Congress")).toHaveLength(2);

        expect(screen.getByText("Baltimore, Maryland, United States")).toBeInTheDocument();
        expect(screen.getByText("3")).toBeInTheDocument();
    });

    it("pluralizes the per-tier locale count", () => {
        render(<Locales tiers={tiers} />);

        expect(screen.getByText("2 locales")).toBeInTheDocument();
        expect(screen.getAllByText("1 locale")).toHaveLength(2); // state + congress each have one
    });

    it("shows an empty message for a tier with no locales", () => {
        const empty = tiers.map((tier) => ({ ...tier, locales: [] }));
        render(<Locales tiers={empty} />);

        expect(screen.getAllByText("No locales yet.")).toHaveLength(3);
        expect(screen.getAllByText("0 locales")).toHaveLength(3);
    });

    it("names the toggle for what the locale already carries", () => {
        render(<Locales tiers={tiers} />);

        expect(screen.getAllByRole("button", { name: "Sample address" })).toHaveLength(1);
        expect(screen.getAllByRole("button", { name: "Add sample address" })).toHaveLength(3);
    });

    it("reveals the four fields, filled from the row, when the toggle is pressed", () => {
        render(<Locales tiers={tiers} />);

        fireEvent.click(screen.getByRole("button", { name: "Sample address" }));

        expect(screen.getByLabelText("Street")).toHaveValue("100 N Holliday St");
        expect(screen.getByLabelText("Postal code")).toHaveValue("21202");
        expect(screen.getByLabelText("Latitude")).toHaveValue("39.29105");
        expect(screen.getByLabelText("Longitude")).toHaveValue("-76.61069");
    });

    it("patches the locale's own path on submit", () => {
        render(<Locales tiers={tiers} />);

        fireEvent.click(screen.getByRole("button", { name: "Sample address" }));
        fireEvent.click(screen.getByRole("button", { name: "Save sample address" }));

        expect(patch).toHaveBeenCalledWith("/admin/locales/1", { preserveScroll: true });
    });

    it("renders a Summarization toggle button for every locale row", () => {
        render(<Locales tiers={tiers} />);

        expect(screen.getAllByRole("button", { name: "Summarization" })).toHaveLength(4);
    });

    it("reveals read-only newsroom sources with path policy badges and legislative body makeup when toggled", () => {
        render(<Locales tiers={tiers} />);

        const summarizationButtons = screen.getAllByRole("button", { name: "Summarization" });
        fireEvent.click(summarizationButtons[0]!);

        expect(screen.getByText("Authoritative · Locale configuration")).toBeInTheDocument();
        expect(
            screen.getByText(/Trusted local newsroom websites used to search and cite reporting for bill summaries/i),
        ).toBeInTheDocument();
        expect(screen.getByText("https://www.thebanner.com/baltimore/")).toBeInTheDocument();
        expect(screen.getByText("https://baltimorebrew.com/")).toBeInTheDocument();
        expect(screen.getByText("Search hint")).toBeInTheDocument();
        expect(screen.getByText("Restricted path")).toBeInTheDocument();
        expect(screen.getByText("Immutable · Prompt defense")).toBeInTheDocument();
        expect(screen.getByText("A 15-member legislative body.")).toBeInTheDocument();

        // Ensure neither news sources nor legislative_body_makeup has an editable input/textarea or submit button
        expect(screen.queryByRole("textbox", { name: /news media/i })).not.toBeInTheDocument();
        expect(screen.queryByRole("textbox", { name: /newsroom sources/i })).not.toBeInTheDocument();
        expect(screen.queryByRole("textbox", { name: /legislative body makeup/i })).not.toBeInTheDocument();
        expect(screen.queryByRole("button", { name: /save summarization settings/i })).not.toBeInTheDocument();
    });

    it("shows empty state when no legislative body makeup is declared", () => {
        render(<Locales tiers={tiers} />);

        const summarizationButtons = screen.getAllByRole("button", { name: "Summarization" });
        fireEvent.click(summarizationButtons[1]!);

        expect(screen.getByText("No legislative body description declared for this jurisdiction.")).toBeInTheDocument();
    });

    it("shows explicit empty state when no newsroom sources are configured", () => {
        render(<Locales tiers={tiers} />);

        const summarizationButtons = screen.getAllByRole("button", { name: "Summarization" });
        fireEvent.click(summarizationButtons[1]!);

        expect(
            screen.getByText("No newsroom sources configured for this jurisdiction. News discovery is disabled."),
        ).toBeInTheDocument();
    });
});
