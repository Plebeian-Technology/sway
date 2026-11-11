// @lat: [[registration-funnel-telemetry#Admin registration funnel dashboard]]
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerGetMock = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a>,
    router: {
        get: (...args: unknown[]) => routerGetMock(...args),
    },
    usePoll: vi.fn<() => void>(),
}));

import RegistrationFunnelIndex, { type IFunnelData } from "app/frontend/pages/admin/RegistrationFunnel/Index";

const sampleFunnelData: IFunnelData = {
    time_range: "30d",
    filter_attribution_key: null,
    overall_conversion_rate: 25.0,
    steps: [
        {
            step: "landing",
            label: "Landing Page",
            visitor_count: 100,
            step_conversion_rate: 100.0,
            drop_off_count: 20,
            drop_off_rate: 20.0,
            conversion_rate_from_start: 100.0,
        },
        {
            step: "phone_entered",
            label: "Phone Entered",
            visitor_count: 80,
            step_conversion_rate: 80.0,
            drop_off_count: 10,
            drop_off_rate: 12.5,
            conversion_rate_from_start: 80.0,
        },
        {
            step: "sms_verified",
            label: "SMS Verified",
            visitor_count: 70,
            step_conversion_rate: 87.5,
            drop_off_count: 15,
            drop_off_rate: 21.4,
            conversion_rate_from_start: 70.0,
        },
        {
            step: "passkey_enrolled",
            label: "Passkey Enrolled",
            visitor_count: 55,
            step_conversion_rate: 78.6,
            drop_off_count: 15,
            drop_off_rate: 27.3,
            conversion_rate_from_start: 55.0,
        },
        {
            step: "address_submitted",
            label: "Address Submitted",
            visitor_count: 40,
            step_conversion_rate: 72.7,
            drop_off_count: 10,
            drop_off_rate: 25.0,
            conversion_rate_from_start: 40.0,
        },
        {
            step: "registration_completed",
            label: "Registration Completed",
            visitor_count: 30,
            step_conversion_rate: 75.0,
            drop_off_count: 5,
            drop_off_rate: 16.7,
            conversion_rate_from_start: 30.0,
        },
        {
            step: "first_vote_cast",
            label: "First Vote Cast",
            visitor_count: 25,
            step_conversion_rate: 83.3,
            drop_off_count: 0,
            drop_off_rate: 0.0,
            conversion_rate_from_start: 25.0,
        },
    ],
    friction_points: [
        {
            from_step: "landing",
            to_step: "phone_entered",
            label: "Landing Page → Phone Entered",
            drop_off_count: 20,
            drop_off_rate: 20.0,
            rank_by_count: 1,
            rank_by_rate: 4,
        },
        {
            from_step: "passkey_enrolled",
            to_step: "address_submitted",
            label: "Passkey Enrolled → Address Submitted",
            drop_off_count: 15,
            drop_off_rate: 27.3,
            rank_by_count: 2,
            rank_by_rate: 1,
        },
    ],
    attributions: [
        {
            source: "s:advocacy_sms",
            visitors_count: 60,
            registrations_count: 20,
            votes_count: 18,
            conversion_rate: 33.3,
            vote_rate: 30.0,
        },
        {
            source: "direct",
            visitors_count: 40,
            registrations_count: 10,
            votes_count: 7,
            conversion_rate: 25.0,
            vote_rate: 17.5,
        },
    ],
    latency: {
        sample_count: 30,
        avg_seconds: 1.85,
        median_seconds: 1.62,
        p95_seconds: 3.45,
        min_seconds: 0.85,
        max_seconds: 4.12,
    },
    time_ranges: [
        { id: "24h", label: "Last 24 Hours" },
        { id: "7d", label: "Last 7 Days" },
        { id: "30d", label: "Last 30 Days" },
        { id: "all", label: "All Time" },
    ],
    traffic: "humans",
    traffic_options: [
        { id: "humans", label: "Humans" },
        { id: "bots", label: "Bots" },
        { id: "all", label: "All" },
    ],
    bot_visitor_count: 4321,
};

describe("RegistrationFunnelIndex", () => {
    afterEach(() => {
        cleanup();
        vi.clearAllMocks();
    });

    it("renders headline metrics and conversion rates", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        expect(screen.getByRole("heading", { level: 1, name: "Registration Funnel" })).toBeInTheDocument();
        expect(screen.getAllByText("25%").length).toBeGreaterThanOrEqual(1); // Overall conversion rate
        expect(screen.getByText("100")).toBeInTheDocument(); // Total Visitors
        expect(screen.getAllByText("30").length).toBeGreaterThanOrEqual(1); // Completed Registrations
        expect(screen.getAllByText("1.62s").length).toBeGreaterThanOrEqual(1); // Median Latency
    });

    it("renders all 7 funnel steps with visitor counts and labels", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        expect(screen.getByText("Landing Page")).toBeInTheDocument();
        expect(screen.getByText("Phone Entered")).toBeInTheDocument();
        expect(screen.getByText("SMS Verified")).toBeInTheDocument();
        expect(screen.getByText("Passkey Enrolled")).toBeInTheDocument();
        expect(screen.getByText("Address Submitted")).toBeInTheDocument();
        expect(screen.getByText("Registration Completed")).toBeInTheDocument();
        expect(screen.getByText("First Vote Cast")).toBeInTheDocument();
    });

    it("toggles friction point ranking between count and rate", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        const rateButton = screen.getByRole("button", { name: "Drop-off %" });
        expect(rateButton).toBeInTheDocument();
        fireEvent.click(rateButton);

        // Under rate ranking, rank 1 is Passkey Enrolled → Address Submitted (27.3%)
        expect(screen.getByText(/Passkey Enrolled → Address Submitted/i)).toBeInTheDocument();
    });

    it("handles time range changes via router.get", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        const sevenDayButton = screen.getByRole("button", { name: "Last 7 Days" });
        fireEvent.click(sevenDayButton);

        expect(routerGetMock).toHaveBeenCalledWith(
            expect.any(String),
            expect.objectContaining({ time_range: "7d" }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("displays referral attribution sources", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        expect(screen.getByText("s:advocacy_sms")).toBeInTheDocument();
        expect(screen.getByText("direct")).toBeInTheDocument();
        expect(screen.getByText("33.3%")).toBeInTheDocument(); // Conversion rate for advocacy_sms
    });

    it("displays latency percentiles", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        expect(screen.getByText("3.45s")).toBeInTheDocument();
        expect(screen.getByText(/Range: 0.85s – 4.12s/)).toBeInTheDocument();
    });

    it("marks the selected traffic option and shows the filtered bot visitor count", () => {
        render(<RegistrationFunnelIndex funnel={sampleFunnelData} />);

        expect(screen.getByRole("button", { name: "Humans" })).toHaveAttribute("aria-pressed", "true");
        expect(screen.getByRole("button", { name: "Bots" })).toHaveAttribute("aria-pressed", "false");
        expect(screen.getByText(/Bot visitors filtered out:/)).toBeInTheDocument();
        expect(screen.getByText("4,321")).toBeInTheDocument();
    });

    it("requests bot-only traffic while keeping the time range and attribution filters", () => {
        render(
            <RegistrationFunnelIndex
                funnel={{ ...sampleFunnelData, time_range: "7d", filter_attribution_key: "s:advocacy_sms" }}
            />,
        );

        fireEvent.click(screen.getByRole("button", { name: "Bots" }));

        expect(routerGetMock).toHaveBeenCalledWith(
            expect.any(String),
            { time_range: "7d", attribution_key: "s:advocacy_sms", traffic: "bots" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("keeps a non-default traffic filter when the time range changes", () => {
        render(<RegistrationFunnelIndex funnel={{ ...sampleFunnelData, traffic: "all" }} />);

        expect(screen.getByText(/Bot visitors in range:/)).toBeInTheDocument();
        fireEvent.click(screen.getByRole("button", { name: "Last 24 Hours" }));

        expect(routerGetMock).toHaveBeenCalledWith(
            expect.any(String),
            expect.objectContaining({ time_range: "24h", traffic: "all" }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("omits the default humans traffic value from the query", () => {
        render(<RegistrationFunnelIndex funnel={{ ...sampleFunnelData, traffic: "bots" }} />);

        fireEvent.click(screen.getByRole("button", { name: "Humans" }));

        expect(routerGetMock).toHaveBeenCalledWith(
            expect.any(String),
            expect.objectContaining({ traffic: undefined }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });
});
