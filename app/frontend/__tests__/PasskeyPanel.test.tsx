// @lat: [[passkey-panel-test-design#Why the throttle latch has to expire]]

import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Grab the setThrottledUntil function the panel passes to each auth hook. All
// three get the very same one, so grabbing it from one hook is enough.
const captured = vi.hoisted(() => ({
    setThrottled: null as ((d: Date | null) => void) | null,
    startAuthentication: vi.fn<() => Promise<unknown>>(),
    startDiscoverableAuthentication: vi.fn<() => Promise<unknown>>(),
    verifyAuthentication: vi.fn<(phone: string, data: unknown) => Promise<void>>(),
    verifyDiscoverableAuthentication: vi.fn<(data: unknown) => Promise<void>>(),
    sendPhoneVerification: vi.fn<(phone: string) => Promise<boolean>>(),
    notify: vi.fn<(...args: unknown[]) => void>(),
    // The panel reads this straight off the hook, so a test can put the panel
    // into the after-a-failure state without running a WebAuthn ceremony.
    discoverableFailure: null as string | null,
    confirm: vi.fn<(phone: string, code: string) => Promise<void>>(),
    clearPasskeyDismissed: vi.fn<() => void>(),
    passkeyDismissed: false,
}));

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: { errors: {} } }),
    Link: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a>,
}));

vi.mock("app/frontend/sway_utils", async (importOriginal) => ({
    ...(await importOriginal<typeof import("app/frontend/sway_utils")>()),
    notify: (...args: unknown[]) => captured.notify(...args),
}));

vi.mock("app/frontend/hooks/authentication/useWebAuthnAuthentication", () => ({
    useWebAuthnAuthentication: (setThrottled: (d: Date | null) => void) => {
        captured.setThrottled = setThrottled;
        return {
            startAuthentication: captured.startAuthentication,
            verifyAuthentication: captured.verifyAuthentication,
            startDiscoverableAuthentication: captured.startDiscoverableAuthentication,
            verifyDiscoverableAuthentication: captured.verifyDiscoverableAuthentication,
            discoverableFailure: captured.discoverableFailure,
            isLoading: false,
        };
    },
}));
vi.mock("app/frontend/hooks/authentication/phone/useSendPhoneVerification", () => ({
    useSendPhoneVerification: () => ({ send: captured.sendPhoneVerification, isLoading: false }),
}));
vi.mock("app/frontend/hooks/authentication/phone/useConfirmPhoneVerification", () => ({
    useConfirmPhoneVerification: () => ({
        confirm: captured.confirm,
        isLoading: false,
        passkeyDismissed: captured.passkeyDismissed,
        clearPasskeyDismissed: captured.clearPasskeyDismissed,
    }),
}));

import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import passkeyPanelSource from "app/frontend/components/auth/PasskeyPanel.tsx?raw";

beforeEach(() => {
    vi.useFakeTimers();
    captured.startAuthentication.mockReset();
    captured.verifyAuthentication.mockReset();
    captured.verifyDiscoverableAuthentication.mockReset();
    captured.startDiscoverableAuthentication.mockReset();
    captured.startDiscoverableAuthentication.mockResolvedValue(undefined);
    captured.sendPhoneVerification.mockReset();
    captured.notify.mockReset();
    captured.discoverableFailure = null;
    captured.confirm.mockReset();
    captured.clearPasskeyDismissed.mockReset();
    captured.passkeyDismissed = false;
});

afterEach(() => {
    cleanup();
    vi.useRealTimers();
    captured.setThrottled = null;
});

// @lat: [[inertia-error-response-headers-shape#Why Inertia's rejected-request headers are a plain object, not Headers]]
const xhrRejection = (status: number) => ({
    response: { status, headers: { "content-type": "application/json" }, data: {} },
});

const submitPhone = async () => {
    fireEvent.change(screen.getByLabelText(/phone/i), { target: { value: "4105551234" } });
    const form = document.querySelector("form") as HTMLFormElement;
    await act(async () => {
        fireEvent.submit(form);
    });
};

describe("PasskeyPanel — throttle latch expiry", () => {
    it("disables submit on throttle and re-enables it when the window elapses", () => {
        const { container } = render(<PasskeyPanel />);
        const submit = () => container.querySelector('button[type="submit"]') as HTMLButtonElement;

        expect(submit().disabled).toBe(false);

        act(() => {
            captured.setThrottled?.(new Date(Date.now() + 60_000));
        });
        expect(submit().disabled).toBe(true);

        act(() => {
            vi.advanceTimersByTime(60_001);
        });
        expect(submit().disabled).toBe(false);
    });

    // @lat: [[passkey-panel-test-design#Why the code-input binding check is deliberately weak]]
    it("binds the code input value (controlled)", () => {
        expect(passkeyPanelSource).toMatch(/value=\{code\}/);
    });
});

// @lat: [[passkey-panel-test-design#Why an unhandled sign-in error can't fail silently]]
describe("PasskeyPanel — a sign-in the server could not complete", () => {
    beforeEach(() => {
        // These tests wait on a rejected promise, and waitFor cannot move
        // forward under the fake clock the rate-limit tests above install.
        vi.useRealTimers();
        // jsdom implements neither of these; the 422 path shows the code field
        // and scrolls it into view.
        Element.prototype.scrollIntoView = vi.fn<(options?: ScrollIntoViewOptions) => void>();
    });

    it.each([
        [500, "the server failed"],
        [502, "the proxy failed"],
    ])("says so on a %i (%s)", async (status) => {
        captured.startAuthentication.mockRejectedValue(xhrRejection(status));
        render(<PasskeyPanel />);

        await submitPhone();

        await waitFor(() => expect(captured.notify).toHaveBeenCalledWith(expect.objectContaining({ level: "error" })));
    });

    // A dropped connection fails with no `.response` at all, so code that only
    // reads the status sees undefined and falls through the same hole.
    it("says so when the request never reached the server", async () => {
        captured.startAuthentication.mockRejectedValue(new TypeError("Failed to fetch"));
        render(<PasskeyPanel />);

        await submitPhone();

        await waitFor(() => expect(captured.notify).toHaveBeenCalledWith(expect.objectContaining({ level: "error" })));
    });

    // @lat: [[passkey-panel-test-design#Why the 422 SMS-fallback case must stay silent]]
    it("stays quiet on the 422 SMS fallback, which is a branch and not a failure", async () => {
        captured.startAuthentication.mockRejectedValue(xhrRejection(422));
        captured.sendPhoneVerification.mockResolvedValue(true);
        render(<PasskeyPanel />);

        await submitPhone();

        expect(captured.sendPhoneVerification).toHaveBeenCalledWith("4105551234");
        expect(captured.notify).not.toHaveBeenCalled();
    });
});

// @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
describe("PasskeyPanel — a passkey attempt that failed for a reason nobody caused", () => {
    it("says nothing when the hook read the failure as a cancel", () => {
        captured.discoverableFailure = null;
        render(<PasskeyPanel />);

        expect(screen.queryByTestId("passkey-fallback-notice")).toBeNull();
    });

    it("names the failure and points at the phone form", () => {
        captured.discoverableFailure = "refused-before-any-prompt";
        render(<PasskeyPanel />);

        const notice = screen.getByTestId("passkey-fallback-notice");
        expect(notice.textContent).toBe(PARITY_COPY.auth.passkeyPanel.passkeyFallback);
        expect(notice.getAttribute("role")).toBe("alert");
    });

    // Naming no cause is the point: the browser will not say which failure it was.
    it("shows no error name or message from the failure itself", () => {
        captured.discoverableFailure = "dom-exception-SecurityError";
        render(<PasskeyPanel />);

        expect(screen.getByTestId("passkey-fallback-notice").textContent).not.toMatch(/SecurityError/);
    });

    it("primes the phone field, so the route forward has focus", () => {
        captured.discoverableFailure = "challenge-request-failed";
        render(<PasskeyPanel />);

        const phone = screen.getByLabelText(/phone/i);
        expect(document.activeElement).toBe(phone);
        expect(phone.getAttribute("aria-describedby")).toContain("v2-passkey-fallback");
    });
});

it("reports a rejected discoverable verification instead of leaving an unhandled promise", async () => {
    captured.startDiscoverableAuthentication.mockResolvedValue({ id: "cred-1" });
    captured.verifyDiscoverableAuthentication.mockRejectedValue(new Error("verification failed"));
    render(<PasskeyPanel />);
    await act(async () => {
        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.auth.passkeyPanel.signInWithPasskey }));
    });
    expect(captured.notify).toHaveBeenCalledWith({ level: "error", title: PARITY_COPY.auth.passkeyPanel.signInError });
});

describe("PasskeyPanel — a dismissed browser passkey prompt", () => {
    beforeEach(() => {
        vi.useRealTimers();
        Element.prototype.scrollIntoView = vi.fn<(options?: ScrollIntoViewOptions) => void>();
        captured.startAuthentication.mockResolvedValue(true);
    });

    const openCodeStep = async () => {
        await submitPhone();
        await screen.findByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel);
    };

    it("shows the retry message on the code step", async () => {
        captured.passkeyDismissed = true;
        render(<PasskeyPanel />);
        await openCodeStep();

        expect(screen.getByText(PARITY_COPY.auth.passkeyPanel.passkeyDismissed)).toBeTruthy();
    });

    it("shows no message when the prompt was not dismissed", async () => {
        render(<PasskeyPanel />);
        await openCodeStep();

        expect(screen.queryByText(PARITY_COPY.auth.passkeyPanel.passkeyDismissed)).toBeNull();
    });

    it("confirms the code again when Confirm code is pressed", async () => {
        captured.passkeyDismissed = true;
        render(<PasskeyPanel />);
        await openCodeStep();
        fireEvent.change(screen.getByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel), {
            target: { value: "123456" },
        });

        await act(async () => {
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.auth.passkeyPanel.confirmCode }));
        });

        expect(captured.confirm).toHaveBeenCalledWith("4105551234", "123456");
    });

    it("clears the dismissal when Cancel is pressed", async () => {
        captured.passkeyDismissed = true;
        render(<PasskeyPanel />);
        await openCodeStep();

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.auth.passkeyPanel.cancelCta }));

        expect(captured.clearPasskeyDismissed).toHaveBeenCalled();
    });
});
