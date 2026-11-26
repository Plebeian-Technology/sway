import React from "react";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

const mockAddListener = jest.fn(() => jest.fn());
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ addListener: mockAddListener }),
}));

import RegistrationFunnelScreen from "../../../src/screens/admin/RegistrationFunnelScreen";

const funnel = (overrides: Record<string, unknown> = {}) => ({
    time_range: "30d",
    filter_attribution_key: null,
    steps: [
        {
            step: "landing",
            label: "Landing Page",
            visitor_count: 1200,
            step_conversion_rate: 100,
            drop_off_count: 0,
            drop_off_rate: 0,
            conversion_rate_from_start: 100,
        },
        {
            step: "phone_entered",
            label: "Phone Entered",
            visitor_count: 600,
            step_conversion_rate: 50,
            drop_off_count: 600,
            drop_off_rate: 50,
            conversion_rate_from_start: 50,
        },
        {
            step: "registration_completed",
            label: "Registration Completed",
            visitor_count: 300,
            step_conversion_rate: 75,
            drop_off_count: 100,
            drop_off_rate: 25,
            conversion_rate_from_start: 25,
        },
        {
            step: "first_vote_cast",
            label: "First Vote Cast",
            visitor_count: 120,
            step_conversion_rate: 40,
            drop_off_count: 180,
            drop_off_rate: 60,
            conversion_rate_from_start: 10,
        },
    ],
    overall_conversion_rate: 10,
    friction_points: [
        {
            from_step: "registration_completed",
            to_step: "first_vote_cast",
            label: "Registration Completed → First Vote Cast",
            drop_off_count: 180,
            drop_off_rate: 60,
            rank_by_count: 2,
            rank_by_rate: 1,
        },
        {
            from_step: "landing",
            to_step: "phone_entered",
            label: "Landing Page → Phone Entered",
            drop_off_count: 600,
            drop_off_rate: 50,
            rank_by_count: 1,
            rank_by_rate: 2,
        },
    ],
    attributions: [
        {
            source: "s:campaign",
            visitors_count: 400,
            registrations_count: 80,
            votes_count: 20,
            conversion_rate: 20,
            vote_rate: 5,
        },
    ],
    latency: {
        sample_count: 12,
        avg_seconds: 3.2,
        median_seconds: 2.5,
        p95_seconds: 9.1,
        min_seconds: 0.4,
        max_seconds: 14,
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
    bot_visitor_count: 42,
    ...overrides,
});

// @lat: [[mobile-admin-area#The registration funnel screen]]
describe("RegistrationFunnelScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("shows the funnel steps with their counts", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("Landing Page")).toBeTruthy();
        expect(screen.getByText("1,200 visitors")).toBeTruthy();
        expect(screen.getByText("Phone Entered")).toBeTruthy();
        expect(screen.getByText("600 visitors")).toBeTruthy();
        expect(screen.getByText("50% step conversion")).toBeTruthy();
        expect(screen.getByText("(600 dropped / 50%)")).toBeTruthy();
        expect(screen.getByText("Registration Completed")).toBeTruthy();
        expect(screen.getByText("300 visitors")).toBeTruthy();
        expect(screen.getByText("First Vote Cast")).toBeTruthy();
        expect(screen.getByText("120 visitors")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/registration_funnel?time_range=30d", expect.anything());
    });

    it("draws each step's bar as its share of the landing visitors", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("Landing Page");

        expect(screen.getByTestId("admin-registration-funnel-bar-landing")).toHaveStyle({ width: "100%" });
        expect(screen.getByTestId("admin-registration-funnel-bar-phone_entered")).toHaveStyle({ width: "50%" });
        expect(screen.getByTestId("admin-registration-funnel-bar-first_vote_cast")).toHaveStyle({ width: "10%" });
    });

    it("shows the four headline figures", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("Landing Page");

        expect(screen.getByText("Landing Visitors")).toBeTruthy();
        expect(screen.getByTestId("admin-registration-funnel-landing-visitors")).toHaveTextContent("1,200");
        expect(screen.getByTestId("admin-registration-funnel-completed-registrations")).toHaveTextContent("300");
        expect(screen.getByText("25.0% of visitors")).toBeTruthy();
        expect(screen.getByTestId("admin-registration-funnel-first-votes")).toHaveTextContent("120");
        expect(screen.getByTestId("admin-registration-funnel-overall-conversion")).toHaveTextContent("10%");
        expect(screen.getByText("Landing → First Vote")).toBeTruthy();
    });

    it("refetches with the time_range query when a range is chosen", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("Landing Page");

        mockApiGet.mockResolvedValue(funnel({ time_range: "7d" }));
        fireEvent.press(screen.getByText("Last 7 Days"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith("/admin/registration_funnel?time_range=7d", expect.anything()),
        );
    });

    it("refetches with the traffic query and keeps the time range", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("Landing Page");

        fireEvent.press(screen.getByText("Last 7 Days"));
        fireEvent.press(screen.getByText("Bots"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith(
                "/admin/registration_funnel?time_range=7d&traffic=bots",
                expect.anything(),
            ),
        );
    });

    it("says how many bot visitors are filtered out or in range", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("Bot visitors filtered out: 42")).toBeTruthy();

        mockApiGet.mockResolvedValue(funnel({ traffic: "bots" }));
        fireEvent.press(screen.getByText("Bots"));

        expect(await screen.findByText("Bot visitors in range: 42")).toBeTruthy();
    });

    it("filters by a referral source and clears the filter", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("s:campaign");

        mockApiGet.mockResolvedValue(funnel({ filter_attribution_key: "s:campaign" }));
        fireEvent.press(screen.getByTestId("admin-registration-funnel-inspect-s:campaign"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith(
                "/admin/registration_funnel?time_range=30d&attribution_key=s%3Acampaign",
                expect.anything(),
            ),
        );
        expect(await screen.findByText("Filtered by referral source: s:campaign")).toBeTruthy();

        mockApiGet.mockResolvedValue(funnel());
        fireEvent.press(screen.getByText("Clear Filter"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith("/admin/registration_funnel?time_range=30d", expect.anything()),
        );
        await waitFor(() => expect(screen.queryByText("Clear Filter")).toBeNull());
    });

    it("lists the referral sources with their figures", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("s:campaign")).toBeTruthy();
        expect(screen.getByText("400 visitors · 80 registrations · 20 first votes")).toBeTruthy();
        expect(screen.getByText("20% conversion")).toBeTruthy();
        expect(screen.getByText("5% vote rate")).toBeTruthy();
    });

    it("says so when no referral source was recorded", async () => {
        mockApiGet.mockResolvedValue(funnel({ attributions: [] }));
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("No attribution events recorded in this time range.")).toBeTruthy();
    });

    it("ranks friction points by lost users, then by drop-off rate", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("Top Friction Points");

        const labels = () =>
            screen
                .getAllByTestId(/^admin-registration-funnel-friction-\d+$/)
                .map(
                    (row) =>
                        `${within(row).getByText(/^#\d+$/).props.children} ${within(row).getByText(/ → /).props.children}`,
                );
        expect(labels()).toEqual(["#1 Landing Page → Phone Entered", "#2 Registration Completed → First Vote Cast"]);
        expect(screen.getByText("600 users dropped")).toBeTruthy();
        expect(screen.getByText("600 users (50%)")).toBeTruthy();

        fireEvent.press(screen.getByText("Drop-off %"));

        expect(labels()).toEqual(["#1 Registration Completed → First Vote Cast", "#2 Landing Page → Phone Entered"]);
    });

    it("says so when there are no friction points", async () => {
        mockApiGet.mockResolvedValue(funnel({ friction_points: [] }));
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("No drop-off events recorded in this period.")).toBeTruthy();
    });

    it("shows the geocoding latency and calls a fast median healthy", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("2.5s")).toBeTruthy();
        expect(screen.getByText("9.1s")).toBeTruthy();
        expect(screen.getByText("3.2s")).toBeTruthy();
        expect(screen.getByText("Range: 0.4s – 14s")).toBeTruthy();
        expect(screen.getByText("12")).toBeTruthy();
        expect(screen.getByText("Geocoding performance is healthy (<5s median).")).toBeTruthy();
    });

    it("warns when the median latency is above five seconds", async () => {
        mockApiGet.mockResolvedValue(
            funnel({
                latency: {
                    sample_count: 3,
                    avg_seconds: 8,
                    median_seconds: 7.5,
                    p95_seconds: 12,
                    min_seconds: 2,
                    max_seconds: 13,
                },
            }),
        );
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("Elevated geocoding latency detected.")).toBeTruthy();
    });

    it("says so when no geocoding was recorded", async () => {
        mockApiGet.mockResolvedValue(
            funnel({
                latency: {
                    sample_count: 0,
                    avg_seconds: 0,
                    median_seconds: 0,
                    p95_seconds: 0,
                    min_seconds: 0,
                    max_seconds: 0,
                },
            }),
        );
        render(<RegistrationFunnelScreen />);

        expect(await screen.findByText("No completed geocoding operations recorded in this time range.")).toBeTruthy();
    });

    it("refetches the funnel when the screen regains focus", async () => {
        mockApiGet.mockResolvedValue(funnel());
        render(<RegistrationFunnelScreen />);
        await screen.findByText("Landing Page");
        expect(mockAddListener).toHaveBeenCalledWith("focus", expect.any(Function));
        const calls = mockApiGet.mock.calls.length;

        const onFocus = (mockAddListener.mock.calls as unknown as [string, () => void][])[0][1];
        await act(async () => {
            onFocus();
        });

        await waitFor(() => expect(mockApiGet.mock.calls.length).toBe(calls + 1));
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<RegistrationFunnelScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});
