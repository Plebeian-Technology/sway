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
    sendPhoneVerification: vi.fn<(phone: string) => Promise<boolean | undefined>>(),
    // When set, a send behaves like the real hook on a 429: it hands this time to the onThrottled it was given.
    sendRefusedUntil: null as Date | null,
    notify: vi.fn<(...args: unknown[]) => void>(),
    // The panel reads this straight off the hook, so a test can put the panel
    // into the after-a-failure state without running a WebAuthn ceremony.
    discoverableFailure: null as string | null,
    confirm: vi.fn<(phone: string, code: string) => Promise<void>>(),
    clearPasskeyDismissed: vi.fn<() => void>(),
    passkeyDismissed: false,
    startRegistration: vi.fn<(phone: string) => Promise<unknown>>(),
    verifyRegistration: vi.fn<(phone: string, credential: unknown) => Promise<void>>(),
    isPasskeySupported: vi.fn<() => boolean>(),
}));

vi.mock("app/frontend/sway_utils/webauthn", () => ({
    isPasskeySupported: () => captured.isPasskeySupported(),
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
vi.mock("app/frontend/hooks/authentication/useWebAuthnRegistration", () => ({
    useWebAuthnRegistration: () => ({
        startRegistration: captured.startRegistration,
        verifyRegistration: captured.verifyRegistration,
        isLoading: false,
    }),
}));
vi.mock("app/frontend/hooks/authentication/phone/useSendPhoneVerification", () => ({
    useSendPhoneVerification: (onThrottled?: (until: Date | null) => void) => ({
        send: async (phone: string) => {
            const result = await captured.sendPhoneVerification(phone);
            if (captured.sendRefusedUntil) {
                onThrottled?.(captured.sendRefusedUntil);
                return undefined;
            }
            return result;
        },
        isLoading: false,
    }),
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
    captured.sendRefusedUntil = null;
    captured.notify.mockReset();
    captured.discoverableFailure = null;
    captured.confirm.mockReset();
    captured.clearPasskeyDismissed.mockReset();
    captured.passkeyDismissed = false;
    captured.startRegistration.mockReset();
    captured.verifyRegistration.mockReset();
    captured.isPasskeySupported.mockReset();
    captured.isPasskeySupported.mockReturnValue(true);
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

describe("PasskeyPanel — the phone step", () => {
    beforeEach(() => {
        vi.useRealTimers();
        Element.prototype.scrollIntoView = vi.fn<(options?: ScrollIntoViewOptions) => void>();
    });

    it("starts passkey enrollment without the code field when this session already confirmed the phone", async () => {
        const credential = { id: "cred-1", type: "public-key" };
        captured.startAuthentication.mockResolvedValue("enroll");
        captured.startRegistration.mockResolvedValue(credential);
        render(<PasskeyPanel />);

        await submitPhone();

        expect(captured.startRegistration).toHaveBeenCalledWith("4105551234");
        expect(captured.verifyRegistration).toHaveBeenCalledWith("4105551234", credential);
        expect(captured.sendPhoneVerification).not.toHaveBeenCalled();
        expect(captured.notify).not.toHaveBeenCalled();
        expect(screen.queryByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel)).toBeNull();
    });

    // @lat: [[passkey-panel-test-design#Why the phone step checks passkey support before any request]]
    it("tells a browser without passkey support so and sends nothing", async () => {
        captured.isPasskeySupported.mockReturnValue(false);
        render(<PasskeyPanel />);

        await submitPhone();

        expect(captured.notify).toHaveBeenCalledWith({
            level: "error",
            title: PARITY_COPY.auth.passkeyPanel.passkeyUnsupported,
        });
        expect(captured.startAuthentication).not.toHaveBeenCalled();
        expect(captured.sendPhoneVerification).not.toHaveBeenCalled();
    });

    it("does not check passkey support when the phone number is not 10 digits", async () => {
        captured.isPasskeySupported.mockReturnValue(false);
        render(<PasskeyPanel />);

        fireEvent.change(screen.getByLabelText(/phone/i), { target: { value: "410" } });
        await act(async () => {
            fireEvent.submit(document.querySelector("form") as HTMLFormElement);
        });

        expect(captured.notify).toHaveBeenCalledWith({
            level: "warning",
            title: PARITY_COPY.auth.passkeyPanel.validationPhone,
        });
        expect(captured.notify).toHaveBeenCalledTimes(1);
    });

    it("says the code could not be sent, and not that the number is wrong, when the send failed", async () => {
        captured.startAuthentication.mockResolvedValue(false);
        render(<PasskeyPanel />);

        await submitPhone();

        expect(captured.notify).toHaveBeenCalledWith({
            level: "error",
            title: PARITY_COPY.auth.passkeyPanel.requestCodeError,
        });
        expect(captured.notify).toHaveBeenCalledTimes(1);
        expect(screen.queryByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel)).toBeNull();
    });

    it("warns about a phone with fewer than 10 digits and starts nothing", async () => {
        render(<PasskeyPanel />);
        fireEvent.change(screen.getByLabelText(/phone/i), { target: { value: "410555" } });

        await act(async () => {
            fireEvent.submit(document.querySelector("form") as HTMLFormElement);
        });

        expect(captured.notify).toHaveBeenCalledWith({
            level: "warning",
            title: PARITY_COPY.auth.passkeyPanel.validationPhone,
        });
        expect(captured.startAuthentication).not.toHaveBeenCalled();
        expect(captured.confirm).not.toHaveBeenCalled();
    });

    it("warns about an empty code and does not confirm", async () => {
        captured.startAuthentication.mockResolvedValue(true);
        render(<PasskeyPanel />);
        await submitPhone();
        await screen.findByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel);

        await act(async () => {
            fireEvent.submit(document.querySelector("form") as HTMLFormElement);
        });

        expect(captured.notify).toHaveBeenCalledWith({
            level: "warning",
            title: "Please enter your confirmation code.",
        });
        expect(captured.confirm).not.toHaveBeenCalled();
    });

    it("returns to the phone form when Cancel is pressed", async () => {
        captured.startAuthentication.mockResolvedValue(true);
        render(<PasskeyPanel />);
        await submitPhone();
        const codeBox = await screen.findByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel);
        fireEvent.change(codeBox, { target: { value: "123" } });
        expect((screen.getByLabelText(/phone/i) as HTMLInputElement).disabled).toBe(true);

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.auth.passkeyPanel.cancelCta }));

        expect(screen.queryByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel)).toBeNull();
        expect((screen.getByLabelText(/phone/i) as HTMLInputElement).disabled).toBe(false);
    });
});

describe("PasskeyPanel — asking for a new code when the first never arrives", () => {
    beforeEach(() => {
        vi.useRealTimers();
        Element.prototype.scrollIntoView = vi.fn<(options?: ScrollIntoViewOptions) => void>();
        captured.startAuthentication.mockResolvedValue(true);
    });

    const openCodeStep = async () => {
        await submitPhone();
        return screen.findByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel);
    };

    const pressResend = async () => {
        await act(async () => {
            fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.auth.passkeyPanel.resendCode }));
        });
    };

    const confirmButton = () =>
        screen.getByRole("button", { name: PARITY_COPY.auth.passkeyPanel.confirmCode }) as HTMLButtonElement;

    it("offers no new-code button on the phone step", () => {
        render(<PasskeyPanel />);

        expect(screen.queryByRole("button", { name: PARITY_COPY.auth.passkeyPanel.resendCode })).toBeNull();
    });

    it("sends a new code, clears the code box and says so", async () => {
        captured.sendPhoneVerification.mockResolvedValue(true);
        render(<PasskeyPanel />);
        const codeBox = (await openCodeStep()) as HTMLInputElement;
        fireEvent.change(codeBox, { target: { value: "123" } });

        await pressResend();

        expect(captured.sendPhoneVerification).toHaveBeenCalledWith("4105551234");
        expect(codeBox.value).toBe("");
        expect(captured.notify).toHaveBeenCalledWith({
            level: "success",
            title: PARITY_COPY.auth.passkeyPanel.codeResent,
        });
    });

    it("sends again each time it is pressed", async () => {
        captured.sendPhoneVerification.mockResolvedValue(true);
        render(<PasskeyPanel />);
        await openCodeStep();

        await pressResend();
        await pressResend();

        expect(captured.sendPhoneVerification).toHaveBeenCalledTimes(2);
    });

    it("keeps the code step and the typed code open when the send fails", async () => {
        captured.sendPhoneVerification.mockResolvedValue(false);
        render(<PasskeyPanel />);
        const codeBox = (await openCodeStep()) as HTMLInputElement;
        fireEvent.change(codeBox, { target: { value: "123" } });

        await pressResend();

        expect(captured.notify).toHaveBeenCalledWith({
            level: "error",
            title: PARITY_COPY.auth.passkeyPanel.requestCodeError,
        });
        expect(codeBox.value).toBe("123");
        expect(confirmButton().disabled).toBe(false);
    });

    // @lat: [[passkey-panel-test-design#Why a refused new-code request must not latch the throttle]]
    it("keeps Confirm code enabled when the request is refused with 429", async () => {
        render(<PasskeyPanel />);
        await openCodeStep();
        captured.sendRefusedUntil = new Date(Date.now() + 60_000);

        await pressResend();

        expect(screen.getByLabelText(PARITY_COPY.auth.passkeyPanel.codeLabel)).toBeTruthy();
        expect(confirmButton().disabled).toBe(false);
    });
});
