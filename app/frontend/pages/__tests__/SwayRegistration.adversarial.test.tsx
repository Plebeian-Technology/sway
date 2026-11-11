// @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
// @lat: [[registration-dead-ends#Reaching sign-in from an expired session]]
// @lat: [[locale-extension#Nominatim geographic configuration]]

import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import type { INominatimPlace } from "app/frontend/sway_utils/parseNominatimAddress";
import { NOMINATIM_USER_AGENT } from "app/frontend/hooks/useNominatimAddressAutocomplete";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";

interface IFormActionOptions {
    onFinish?: () => void;
    [key: string]: unknown;
}

const postMock = vi.fn<(url: string, options?: IFormActionOptions) => void>();
const usePollMock = vi.fn<(interval: number, options?: unknown, config?: unknown) => void>();

vi.mock("@inertiajs/react", () => ({
    useForm: function useForm<TForm extends Record<string, unknown>>(initial: TForm) {
        const [data, setDataState] = React.useState<TForm>(initial ?? ({} as TForm));
        const setData = (keyOrObj: string | Partial<TForm>, val?: unknown) => {
            if (typeof keyOrObj === "string") {
                setDataState((prev) => ({ ...prev, [keyOrObj]: val }));
            } else {
                setDataState((prev) => ({ ...prev, ...keyOrObj }));
            }
        };
        return {
            data,
            setData,
            post: postMock,
            processing: false,
            errors: {},
            transform: vi.fn<(fn: (d: TForm) => TForm) => void>(),
        };
    },
    usePoll: (interval: number, options?: unknown, config?: unknown) => usePollMock(interval, options, config),
    Link: ({ href, children, ...rest }: React.PropsWithChildren<{ href: string }>) => (
        <a href={href} {...(rest as object)}>
            {children}
        </a>
    ),
}));

const mockLogout = vi.fn<() => Promise<void>>();
vi.mock("app/frontend/hooks/users/useLogout", () => ({
    useLogout: () => mockLogout,
}));

const toastDismissMock = vi.fn<() => void>();
vi.mock("react-hot-toast", () => ({
    default: {
        dismiss: () => toastDismissMock(),
    },
}));

interface INotifyParams {
    id?: string;
    level: sway.TAlertLevel;
    title: string | React.JSX.Element;
    message?: string;
    duration?: number;
}

const notifyMock = vi.fn<(args: INotifyParams) => string>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (args: INotifyParams) => notifyMock(args),
    logDev: vi.fn<(...args: unknown[]) => void>(),
}));

const trackFunnelStepMock = vi.fn<(step: string, metadata?: Record<string, unknown>) => void>();
const trackFunnelStepOnceMock = vi.fn<(step: string) => void>();
vi.mock("app/frontend/sway_utils/funnelTracker", () => ({
    trackFunnelStep: (step: string, metadata?: Record<string, unknown>) => trackFunnelStepMock(step, metadata),
    trackFunnelStepOnce: (step: string) => trackFunnelStepOnceMock(step),
}));

import SwayRegistration from "app/frontend/pages/SwayRegistration";

const BALTIMORE_LOCALE: sway.ISwayLocale = {
    id: 1,
    name: "baltimore-maryland-united_states",
    city: "baltimore",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/baltimore-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2024-12-05",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-76.7114,39.3720,-76.5297,39.1972",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
};

const ANNAPOLIS_LOCALE: sway.ISwayLocale = {
    id: 2,
    name: "annapolis-maryland-united_states",
    city: "annapolis",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/annapolis-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2025-01-01",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-76.5392,39.0142,-76.4673,38.9564",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
};

const MARYLAND_LOCALE: sway.ISwayLocale = {
    id: 3,
    name: "maryland-maryland-united_states",
    city: "maryland",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/maryland-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2025-01-08",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-79.4877,39.7230,-75.0489,37.8866",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
};

const CONGRESS_LOCALE: sway.ISwayLocale = {
    id: 4,
    name: "congress-congress-united_states",
    city: "congress",
    region_code: "",
    region_name: "congress",
    country: "united_states",
    icon_url: "public/images/flags/congress-congress-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2025-01-03",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: null,
    nominatim_bounded: false,
    nominatim_country_codes: "us",
};

const SAMPLE_NOMINATIM_PLACE: INominatimPlace = {
    place_id: 100149,
    osm_type: "way",
    osm_id: 424242,
    lat: "39.2904",
    lon: "-76.6122",
    display_name: "100 Holliday Street, Downtown, Baltimore, Maryland, 21202, United States",
    address: {
        house_number: "100",
        road: "Holliday Street",
        suburb: "Downtown",
        city: "Baltimore",
        state: "Maryland",
        postcode: "21202",
        country: "United States",
        country_code: "us",
    },
};

const failedUser: sway.IUser = {
    id: 42,
    registration_status: "failed",
} as sway.IUser;

const completeUser: sway.IUser = {
    id: 42,
    registration_status: "completed",
    is_registration_complete: true,
} as sway.IUser;

describe("SwayRegistration Adversarial Challenge — Workflow & Failure Recovery", () => {
    let windowOpenSpy: ReturnType<typeof vi.spyOn>;
    let originalFetch: typeof global.fetch;

    beforeEach(() => {
        vi.useFakeTimers();
        postMock.mockReset();
        usePollMock.mockReset();
        mockLogout.mockReset();
        toastDismissMock.mockReset();
        notifyMock.mockReset();
        trackFunnelStepMock.mockReset();
        trackFunnelStepOnceMock.mockReset();

        windowOpenSpy = vi.spyOn(window, "open").mockImplementation(() => null);
        originalFetch = global.fetch;
        global.fetch = vi.fn<typeof global.fetch>().mockImplementation(() =>
            Promise.resolve({
                ok: true,
                json: () => Promise.resolve([SAMPLE_NOMINATIM_PLACE]),
            } as Response),
        );
    });

    afterEach(() => {
        cleanup();
        vi.useRealTimers();
        windowOpenSpy.mockRestore();
        global.fetch = originalFetch;
    });

    describe("Active Locale Propagation across all Locales", () => {
        it("propagates Baltimore locale viewbox and bounded params into Nominatim fetch query", async () => {
            render(<SwayRegistration user={failedUser} sway_locale={BALTIMORE_LOCALE} />);
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

            const combobox = screen.getByRole("combobox");
            fireEvent.change(combobox, { target: { value: "100 Holliday" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledTimes(1);
            const calledUrl = (global.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
            const parsedUrl = new URL(calledUrl);

            expect(parsedUrl.searchParams.get("viewbox")).toBe(BALTIMORE_LOCALE.nominatim_viewbox);
            expect(parsedUrl.searchParams.get("bounded")).toBe("1");
            expect(parsedUrl.searchParams.get("countrycodes")).toBe("us");
            expect(parsedUrl.searchParams.get("q")).toBe("100 Holliday");
        });

        it("propagates Annapolis locale viewbox into Nominatim fetch query", async () => {
            render(<SwayRegistration user={failedUser} sway_locale={ANNAPOLIS_LOCALE} />);
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

            const combobox = screen.getByRole("combobox");
            fireEvent.change(combobox, { target: { value: "Main St" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledTimes(1);
            const calledUrl = (global.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
            const parsedUrl = new URL(calledUrl);

            expect(parsedUrl.searchParams.get("viewbox")).toBe(ANNAPOLIS_LOCALE.nominatim_viewbox);
            expect(parsedUrl.searchParams.get("bounded")).toBe("1");
            expect(parsedUrl.searchParams.get("countrycodes")).toBe("us");
        });

        it("propagates Maryland state-wide locale viewbox into Nominatim fetch query", async () => {
            render(<SwayRegistration user={failedUser} sway_locale={MARYLAND_LOCALE} />);
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

            const combobox = screen.getByRole("combobox");
            fireEvent.change(combobox, { target: { value: "State Circle" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledTimes(1);
            const calledUrl = (global.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
            const parsedUrl = new URL(calledUrl);

            expect(parsedUrl.searchParams.get("viewbox")).toBe(MARYLAND_LOCALE.nominatim_viewbox);
            expect(parsedUrl.searchParams.get("bounded")).toBe("1");
            expect(parsedUrl.searchParams.get("countrycodes")).toBe("us");
        });

        it("propagates Congress unbounded locale omitting viewbox and bounded from fetch query", async () => {
            render(<SwayRegistration user={failedUser} sway_locale={CONGRESS_LOCALE} />);
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

            const combobox = screen.getByRole("combobox");
            fireEvent.change(combobox, { target: { value: "Independence Ave" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledTimes(1);
            const calledUrl = (global.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
            const parsedUrl = new URL(calledUrl);

            expect(parsedUrl.searchParams.has("viewbox")).toBe(false);
            expect(parsedUrl.searchParams.has("bounded")).toBe(false);
            expect(parsedUrl.searchParams.get("countrycodes")).toBe("us");
        });

        it("prioritizes locale prop over sway_locale prop when both are provided", async () => {
            render(<SwayRegistration user={failedUser} sway_locale={BALTIMORE_LOCALE} locale={ANNAPOLIS_LOCALE} />);
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

            const combobox = screen.getByRole("combobox");
            fireEvent.change(combobox, { target: { value: "Market St" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledTimes(1);
            const calledUrl = (global.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
            const parsedUrl = new URL(calledUrl);

            expect(parsedUrl.searchParams.get("viewbox")).toBe(ANNAPOLIS_LOCALE.nominatim_viewbox);
        });

        it("gracefully falls back when neither locale nor sway_locale is provided", async () => {
            render(<SwayRegistration user={failedUser} />);
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

            const combobox = screen.getByRole("combobox");
            fireEvent.change(combobox, { target: { value: "Elm St" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledTimes(1);
            const calledUrl = (global.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
            const parsedUrl = new URL(calledUrl);

            expect(parsedUrl.searchParams.has("viewbox")).toBe(false);
            expect(parsedUrl.searchParams.has("bounded")).toBe(false);
            expect(parsedUrl.searchParams.has("countrycodes")).toBe(false);
        });
    });

    describe("Workflow State Transitions & Failure Recovery Cycles", () => {
        it("navigates failed -> retry -> submit -> onFinish failure -> retry recovery loop without crashing", () => {
            let capturedOnFinish: (() => void) | undefined;
            postMock.mockImplementation((_url, options) => {
                capturedOnFinish = options?.onFinish;
            });

            render(<SwayRegistration user={failedUser} />);

            expect(screen.getByTestId("registration-error")).toBeInTheDocument();
            const retryButton = screen.getByTestId("btn-retry-registration");
            expect(retryButton).toBeInTheDocument();

            fireEvent.click(retryButton);
            expect(screen.queryByTestId("registration-error")).toBeNull();
            expect(screen.getByRole("combobox")).toBeInTheDocument();

            const submitButton = screen.getByTestId("btn-submit-registration");
            const form = submitButton.closest("form");
            expect(form).not.toBeNull();
            fireEvent.submit(form!);

            expect(notifyMock).toHaveBeenCalledWith(
                expect.objectContaining({
                    level: "info",
                    title: "Finding your representatives.",
                }),
            );
            expect(postMock).toHaveBeenCalledWith("/sway_registration", expect.any(Object));

            expect(submitButton).toBeDisabled();

            act(() => {
                capturedOnFinish?.();
            });

            expect(toastDismissMock).toHaveBeenCalled();
            expect(screen.getByTestId("registration-error")).toBeInTheDocument();

            fireEvent.click(screen.getByTestId("btn-retry-registration"));
            expect(screen.queryByTestId("registration-error")).toBeNull();
            expect(screen.getByRole("combobox")).toBeInTheDocument();
        });

        it("handles cancel button click by invoking useLogout", () => {
            render(<SwayRegistration user={failedUser} />);
            fireEvent.click(screen.getByTestId("btn-retry-registration"));

            const cancelButton = screen.getByTestId("btn-cancel-registration");
            fireEvent.click(cancelButton);

            expect(mockLogout).toHaveBeenCalledTimes(1);
        });

        it("allows toggling voter registration confirmation checkbox", () => {
            render(<SwayRegistration user={failedUser} />);
            fireEvent.click(screen.getByTestId("btn-retry-registration"));

            const checkbox = screen.getByTestId("registered-voter-address-confirmation");
            expect(checkbox).not.toBeChecked();

            fireEvent.click(checkbox);
            expect(checkbox).toBeChecked();

            fireEvent.click(checkbox);
            expect(checkbox).not.toBeChecked();
        });

        it("dispatches funnel telemetry tracking on mount and status transitions", () => {
            render(<SwayRegistration user={failedUser} />);
            expect(trackFunnelStepOnceMock).toHaveBeenCalledWith("address_form_viewed");
            expect(trackFunnelStepOnceMock).toHaveBeenCalledWith("registration_failed");
        });

        it("tracks completion telemetry when user is registered", () => {
            render(<SwayRegistration user={completeUser} />);
            expect(trackFunnelStepOnceMock).toHaveBeenCalledWith("registration_completed");
        });
    });

    describe("Session Expiration Boundary Challenges", () => {
        it("renders session expired card when user is empty object", () => {
            render(<SwayRegistration user={{} as sway.IUser} />);

            expect(screen.getByText(PARITY_COPY.address.sessionExpired.title)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.address.sessionExpired.message)).toBeInTheDocument();
            const link = screen.getByTestId("link-signin");
            expect(link).toHaveAttribute("href", ROUTES.signin);
            expect(screen.queryByRole("combobox")).toBeNull();
        });

        it("renders session expired card when user id is 0 (falsy id invariant)", () => {
            render(<SwayRegistration user={{ id: 0 } as unknown as sway.IUser} />);

            expect(screen.getByText(PARITY_COPY.address.sessionExpired.title)).toBeInTheDocument();
            expect(screen.getByTestId("link-signin")).toBeInTheDocument();
            expect(screen.queryByRole("combobox")).toBeNull();
        });

        it("renders session expired card when user is null or undefined", () => {
            const { unmount } = render(<SwayRegistration user={null as unknown as sway.IUser} />);
            expect(screen.getByText(PARITY_COPY.address.sessionExpired.title)).toBeInTheDocument();
            unmount();

            render(<SwayRegistration user={undefined as unknown as sway.IUser} />);
            expect(screen.getByText(PARITY_COPY.address.sessionExpired.title)).toBeInTheDocument();
        });
    });

    describe("Processing State & Polling Hook Invariants", () => {
        it("renders processing card and activates usePoll when processing is true", () => {
            render(<SwayRegistration user={failedUser} processing={true} />);

            expect(screen.getByTestId("registration-processing")).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.address.processing.title)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.address.processing.message)).toBeInTheDocument();
            expect(screen.queryByRole("combobox")).toBeNull();
            expect(screen.queryByTestId("registration-error")).toBeNull();

            expect(usePollMock).toHaveBeenCalledWith(3000, { only: ["user", "processing"] }, { autoStart: true });
            expect(trackFunnelStepOnceMock).toHaveBeenCalledWith("geocode_polling_started");
        });
    });

    describe("External Advisory Links", () => {
        it("opens external voter registration and github links in new tab with secure flags", () => {
            render(<SwayRegistration user={failedUser} />);
            fireEvent.click(screen.getByTestId("btn-retry-registration"));

            const registerBtn = screen.getByRole("button", {
                name: new RegExp(PARITY_COPY.address.helper.registerToVote, "i"),
            });
            fireEvent.click(registerBtn);
            expect(windowOpenSpy).toHaveBeenCalledWith(
                PARITY_COPY.address.helper.registerToVoteUrl,
                "_blank",
                "noopener,noreferrer",
            );

            const checkBtn = screen.getByRole("button", {
                name: new RegExp(PARITY_COPY.address.helper.checkRegistration, "i"),
            });
            fireEvent.click(checkBtn);
            expect(windowOpenSpy).toHaveBeenCalledWith(
                PARITY_COPY.address.helper.checkRegistrationUrl,
                "_blank",
                "noopener,noreferrer",
            );

            const githubBtn = screen.getByRole("button", {
                name: new RegExp(PARITY_COPY.address.helper.viewOnGitHub, "i"),
            });
            fireEvent.click(githubBtn);
            expect(windowOpenSpy).toHaveBeenCalledWith(
                PARITY_COPY.address.helper.viewOnGitHubUrl,
                "_blank",
                "noopener,noreferrer",
            );
        });
    });

    describe("Full Unmocked End-to-End Nominatim Autocomplete Integration", () => {
        it("completes full address search, suggestion selection, and form submission lifecycle", async () => {
            render(<SwayRegistration user={failedUser} sway_locale={BALTIMORE_LOCALE} />);
            fireEvent.click(screen.getByTestId("btn-retry-registration"));

            const combobox = screen.getByRole("combobox");
            expect(combobox).toBeInTheDocument();

            fireEvent.change(combobox, { target: { value: "100 Holliday" } });

            await act(async () => {
                vi.advanceTimersByTime(1000);
            });

            expect(global.fetch).toHaveBeenCalledWith(
                expect.any(String),
                expect.objectContaining({
                    headers: expect.objectContaining({
                        "User-Agent": NOMINATIM_USER_AGENT,
                    }),
                }),
            );

            const listbox = screen.getByRole("listbox");
            expect(listbox).toBeInTheDocument();
            expect(screen.getByTestId("osm-attribution")).toBeInTheDocument();

            const option = screen.getByRole("option");
            fireEvent.click(option);

            expect(combobox).toHaveValue(SAMPLE_NOMINATIM_PLACE.display_name);

            const form = screen.getByTestId("btn-submit-registration").closest("form");
            expect(form).not.toBeNull();
            fireEvent.submit(form!);

            expect(trackFunnelStepMock).toHaveBeenCalledWith(
                "address_submitted",
                expect.objectContaining({
                    city: "Baltimore",
                    region_code: "MD",
                }),
            );

            expect(postMock).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
        });
    });
});
