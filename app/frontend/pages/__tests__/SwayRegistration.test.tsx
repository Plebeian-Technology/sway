// @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const post = vi.fn<(url: string, options?: Record<string, unknown>) => void>();
const transform = vi.fn<(callback: (data: Record<string, unknown>) => Record<string, unknown>) => void>();

vi.mock("@inertiajs/react", () => ({
    useForm: function useForm(initial: Record<string, unknown>) {
        const [data, setDataState] = React.useState<Record<string, unknown>>(initial ?? {});
        const setData = (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value }));
        return {
            data,
            setData,
            post,
            processing: false,
            transform,
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

// Mock address autocomplete components to isolate registration page tests from external APIs/networking.
vi.mock("app/frontend/components/user/NominatimAddressAutocomplete", () => ({
    __esModule: true,
    default: ({ locale }: { locale?: sway.ISwayLocale | null }) => (
        <input data-testid="address-field" data-locale={locale?.name ?? ""} />
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
