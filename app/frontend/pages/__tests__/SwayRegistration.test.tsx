// @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const post = vi.fn<(url: string, options?: Record<string, unknown>) => void>();
const transform = vi.fn<(callback: (data: Record<string, unknown>) => Record<string, unknown>) => void>();
let postedBody: Record<string, unknown> | undefined;

vi.mock("@inertiajs/react", () => ({
    useForm: function useForm(initial: Record<string, unknown>) {
        const [data, setDataState] = React.useState<Record<string, unknown>>(initial ?? {});
        const transformRef = React.useRef<((data: Record<string, unknown>) => Record<string, unknown>) | null>(null);
        const setData = (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value }));
        return {
            data,
            setData,
            post: (url: string, options?: Record<string, unknown>) => {
                post(url, options);
                postedBody = transformRef.current ? transformRef.current(data) : data;
            },
            processing: false,
            transform: (callback: (data: Record<string, unknown>) => Record<string, unknown>) => {
                transform(callback);
                transformRef.current = callback;
            },
        };
    },
    usePoll: vi.fn<(interval: number, options?: unknown, config?: unknown) => void>(),
    Link: ({ href, children, ...rest }: React.PropsWithChildren<{ href: string }>) => (
        <a href={href} {...(rest as object)}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/hooks/users/useLogout", () => ({ useLogout: () => () => Promise.resolve() }));

const ROAD_ONLY_SUGGESTION = {
    city: "Baltimore",
    region_code: "MD",
    postal_code: "21202",
    country: "United States",
    latitude: 39.29,
    longitude: -76.61,
};

const COMPLETE_SUGGESTION = { ...ROAD_ONLY_SUGGESTION, street: "100 Holliday Street" };

const { postal_code: _postalCode, ...NO_POSTCODE_SUGGESTION } = COMPLETE_SUGGESTION;

// Mock address autocomplete components to isolate registration page tests from external APIs/networking.
vi.mock("app/frontend/components/user/NominatimAddressAutocomplete", () => ({
    __esModule: true,
    default: ({
        locale,
        form,
    }: {
        locale?: sway.ISwayLocale | null;
        form: { setData: (key: string, value: unknown) => void };
    }) => (
        <>
            <input
                data-testid="address-field"
                data-locale={locale?.name ?? ""}
                onChange={(e) => form.setData("typed_address", e.target.value)}
            />
            <button
                type="button"
                data-testid="pick-suggestion"
                aria-label="pick-suggestion"
                onClick={() => {
                    Object.entries(COMPLETE_SUGGESTION).forEach(([key, value]) => form.setData(key, value));
                }}
            />
            <button
                type="button"
                data-testid="pick-no-postcode-suggestion"
                aria-label="pick-no-postcode-suggestion"
                onClick={() => {
                    Object.entries(NO_POSTCODE_SUGGESTION).forEach(([key, value]) => form.setData(key, value));
                }}
            />
            <button
                type="button"
                data-testid="pick-road-only-suggestion"
                aria-label="pick-road-only-suggestion"
                onClick={() => {
                    Object.entries(ROAD_ONLY_SUGGESTION).forEach(([key, value]) => form.setData(key, value));
                }}
            />
        </>
    ),
}));
vi.mock("app/frontend/components/user/AddressAutocomplete", () => ({
    __esModule: true,
    default: () => <input data-testid="address-field" />,
}));

import SwayRegistration from "app/frontend/pages/SwayRegistration";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";

const failedUser = { id: 4, registration_status: "failed" } as unknown as sway.IUser;

afterEach(cleanup);

beforeEach(() => {
    post.mockReset();
    transform.mockReset();
    postedBody = undefined;
});

describe("SwayRegistration — a failed lookup is not a dead end", () => {
    it("shows the no-representatives outcome alongside the failed status card", () => {
        const safeMessage = "No representatives were found for this address. Check that it is in a supported area.";
        render(
            <SwayRegistration
                user={failedUser}
                registration_outcome={{ reason: "no_representatives", message: safeMessage }}
            />,
        );

        expect(screen.getByTestId("no-representatives-message").textContent).toContain(safeMessage);
        expect(screen.getByTestId("registration-error").textContent).toContain(PARITY_COPY.address.failed.message);
    });

    it("shows a terminal no-representatives outcome instead of a stale processing card", () => {
        const safeMessage =
            "We couldn't find representatives for this address. Check that it is in a Sway-supported area and try again.";
        render(
            <SwayRegistration
                user={{ id: 5, registration_status: "processing" } as unknown as sway.IUser}
                processing
                registration_outcome={{ reason: "no_representatives", message: safeMessage }}
            />,
        );

        expect(screen.getByTestId("no-representatives-message").textContent).toContain(safeMessage);
        expect(screen.queryByTestId("registration-processing")).toBeNull();
        expect(screen.getByTestId("btn-submit-registration")).toBeInTheDocument();
    });

    it("offers a control back to the address form beside the failure message", () => {
        render(<SwayRegistration user={failedUser} />);

        expect(screen.getByTestId("registration-error").textContent).toContain(PARITY_COPY.address.failed.message);
        expect(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta })).toBeInTheDocument();
    });

    it("shows the address form on the same page once that control is pressed", () => {
        render(<SwayRegistration user={failedUser} />);

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

        expect(screen.getByTestId("address-field")).toBeInTheDocument();
        expect(screen.getByTestId("btn-submit-registration")).toBeInTheDocument();
        expect(screen.queryByTestId("registration-error")).toBeNull();
    });

    it("shows the failed card again when the corrected address fails too", () => {
        post.mockImplementation((_url, options) => {
            (options as { onFinish?: () => void } | undefined)?.onFinish?.();
        });
        render(<SwayRegistration user={failedUser} />);

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));
        fireEvent.submit(screen.getByTestId("btn-submit-registration").closest("form")!);

        expect(screen.getByTestId("registration-error")).toBeInTheDocument();
        expect(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta })).toBeInTheDocument();
    });

    it("submits the corrected address to the same endpoint the first one used", () => {
        render(<SwayRegistration user={failedUser} />);

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));
        fireEvent.submit(screen.getByTestId("btn-submit-registration").closest("form")!);

        expect(post).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
    });

    it("passes active locale down to NominatimAddressAutocomplete", () => {
        const mockLocale = { id: 1, name: "baltimore", nominatim_country_codes: "us" } as sway.ISwayLocale;
        render(<SwayRegistration user={failedUser} sway_locale={mockLocale} />);

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.address.failed.retryCta }));

        const input = screen.getByTestId("address-field");
        expect(input).toBeInTheDocument();
        expect(input.getAttribute("data-locale")).toBe("baltimore");
    });
});

// @lat: [[registration-dead-ends#Reaching sign-in from an expired session]]
describe("SwayRegistration — the expired-session card can reach sign-in", () => {
    it("carries a link to the sign-in route", () => {
        render(<SwayRegistration user={{} as sway.IUser} />);

        const link = screen.getByRole("link", { name: PARITY_COPY.address.sessionExpired.cta });
        expect(link.getAttribute("href")).toBe(ROUTES.signin);
    });

    it("says the session is gone in copy the page shares with the rest of registration", () => {
        render(<SwayRegistration user={{} as sway.IUser} />);

        expect(screen.getByText(PARITY_COPY.address.sessionExpired.title)).toBeInTheDocument();
        expect(screen.getByText(PARITY_COPY.address.sessionExpired.message)).toBeInTheDocument();
    });
});

describe("SwayRegistration — address switching confirmation", () => {
    it("renders shared PARITY_COPY.address.switchConfirm copy when a registered user submits and posts on confirm", () => {
        const registeredUser = {
            id: 9,
            registration_status: "completed",
            is_registration_complete: true,
        } as unknown as sway.IUser;
        render(<SwayRegistration user={registeredUser} />);

        fireEvent.submit(screen.getByTestId("btn-submit-registration").closest("form")!);

        expect(post).not.toHaveBeenCalled();
        const dialog = screen.getByTestId("confirm-address-switch-dialog");
        expect(dialog).toBeInTheDocument();
        expect(dialog.querySelector("p")?.textContent).toBe(PARITY_COPY.address.switchConfirm.title);
        expect(screen.getByText(PARITY_COPY.address.switchConfirm.body)).toBeInTheDocument();
        expect(screen.getByTestId("btn-confirm-address-switch").textContent).toBe(
            PARITY_COPY.address.switchConfirm.confirmCta,
        );
        expect(screen.getByTestId("btn-cancel-address-switch").textContent).toBe(
            PARITY_COPY.address.switchConfirm.cancelCta,
        );

        fireEvent.click(screen.getByTestId("btn-confirm-address-switch"));

        expect(screen.queryByTestId("confirm-address-switch-dialog")).toBeNull();
        expect(transform).toHaveBeenCalledTimes(1);
        const transformFn = transform.mock.calls[0][0];
        expect(transformFn({})).toEqual({ confirm_deactivate_legislators: true });
        expect(post).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
    });

    it("requires confirmation when user.address is present and hides the dialog on cancel without posting", () => {
        const userWithAddress = {
            id: 10,
            registration_status: "pending",
            is_registration_complete: false,
            address: { street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202" },
        } as unknown as sway.IUser;
        render(<SwayRegistration user={userWithAddress} />);

        fireEvent.submit(screen.getByTestId("btn-submit-registration").closest("form")!);

        expect(post).not.toHaveBeenCalled();
        expect(screen.getByTestId("confirm-address-switch-dialog")).toBeInTheDocument();

        fireEvent.click(screen.getByTestId("btn-cancel-address-switch"));

        expect(screen.queryByTestId("confirm-address-switch-dialog")).toBeNull();
        expect(post).not.toHaveBeenCalled();
    });

    it("submits directly without confirmation for a first-time user with no existing address", () => {
        const firstTimeUser = {
            id: 11,
            registration_status: "pending",
            is_registration_complete: false,
        } as unknown as sway.IUser;
        render(<SwayRegistration user={firstTimeUser} />);

        fireEvent.submit(screen.getByTestId("btn-submit-registration").closest("form")!);

        expect(screen.queryByTestId("confirm-address-switch-dialog")).toBeNull();
        expect(post).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
    });
});

describe("SwayRegistration — the typed address is submitted as a fact", () => {
    const firstTimeUser = { id: 12, registration_status: "pending", is_registration_complete: false } as sway.IUser;

    const submitForm = () => fireEvent.submit(screen.getByTestId("btn-submit-registration").closest("form")!);
    const typeAddress = (text: string) =>
        fireEvent.change(screen.getByTestId("address-field"), { target: { value: text } });

    it("posts typed text as the street when no suggestion was picked", () => {
        render(<SwayRegistration user={firstTimeUser} />);

        typeAddress("100 Holliday");
        submitForm();

        expect(post).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
        expect(postedBody).toEqual({ is_voter_registration_address_confirmed: false, street: "100 Holliday" });
    });

    it("posts typed text as the street beside a road-only suggestion's other fields", () => {
        render(<SwayRegistration user={firstTimeUser} />);

        typeAddress("100 Holliday St");
        fireEvent.click(screen.getByTestId("pick-road-only-suggestion"));
        submitForm();

        expect(postedBody).toEqual({
            is_voter_registration_address_confirmed: false,
            ...ROAD_ONLY_SUGGESTION,
            street: "100 Holliday St",
        });
    });

    it("posts the suggestion's street and no postal code when the suggestion has none", () => {
        render(<SwayRegistration user={firstTimeUser} />);

        typeAddress("100 Holliday Street");
        fireEvent.click(screen.getByTestId("pick-no-postcode-suggestion"));
        submitForm();

        expect(post).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
        expect(postedBody).toEqual({ is_voter_registration_address_confirmed: false, ...NO_POSTCODE_SUGGESTION });
        expect(postedBody).not.toHaveProperty("postal_code");
    });

    it("posts a complete suggestion without the typed text", () => {
        render(<SwayRegistration user={firstTimeUser} />);

        typeAddress("100 Holl");
        fireEvent.click(screen.getByTestId("pick-suggestion"));
        submitForm();

        expect(postedBody).toEqual({ is_voter_registration_address_confirmed: false, ...COMPLETE_SUGGESTION });
    });

    it("posts without a street when nothing was typed", () => {
        render(<SwayRegistration user={firstTimeUser} />);

        submitForm();

        expect(post).toHaveBeenCalledTimes(1);
        expect(postedBody).toEqual({ is_voter_registration_address_confirmed: false });
    });

    it("keeps the address-switch confirmation in the body beside the typed street", () => {
        const registeredUser = { id: 13, is_registration_complete: true } as sway.IUser;
        render(<SwayRegistration user={registeredUser} />);

        typeAddress("100 Holliday");
        submitForm();
        fireEvent.click(screen.getByTestId("btn-confirm-address-switch"));

        expect(postedBody).toMatchObject({ street: "100 Holliday", confirm_deactivate_legislators: true });
    });
});
