import { beforeEach, describe, expect, it, vi } from "vitest";

const captureMessage = vi.fn<(message: string) => string>();
const captureException = vi.fn<(exception: unknown) => string>();

vi.mock("@sentry/react", () => ({
    captureMessage: (message: string) => captureMessage(message),
    captureException: (error: unknown) => captureException(error),
}));

let mockIsProduction = true;
let mockIsMobilePhone = false;

vi.mock("app/frontend/sway_constants", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_constants")>();
    return {
        ...actual,
        get IS_PRODUCTION() {
            return mockIsProduction;
        },
        get IS_MOBILE_PHONE() {
            return mockIsMobilePhone;
        },
        get IS_NOT_PRODUCTION() {
            return !mockIsProduction;
        },
    };
});

const toastMock = vi.fn<(...args: unknown[]) => string>();
const toastErrorMock = vi.fn<(...args: unknown[]) => string>();
const toastSuccessMock = vi.fn<(...args: unknown[]) => string>();
const toastDismissMock = vi.fn<(id?: string) => void>();

vi.mock("react-hot-toast", () => {
    const fn = (...args: unknown[]) => toastMock(...args);
    fn.error = (...args: unknown[]) => toastErrorMock(...args);
    fn.success = (...args: unknown[]) => toastSuccessMock(...args);
    fn.dismiss = (id?: string) => toastDismissMock(id);
    return {
        default: fn,
    };
});

import { handleError } from "app/frontend/sway_utils";

// @lat: [[browser-error-reporting#An omitted message must not create a second event]]
describe("handleError (Stop handleError emitting empty Sentry messages)", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        mockIsProduction = true;
        mockIsMobilePhone = false;
    });

    it("emits only captureException and no captureMessage when message is omitted", () => {
        const error = new Error("Direct upload failed");
        handleError(error);

        expect(captureException).toHaveBeenCalledTimes(1);
        expect(captureException).toHaveBeenCalledWith(error);
        expect(captureMessage).not.toHaveBeenCalled();

        expect(toastErrorMock).toHaveBeenCalledWith(
            "Error in Sway. Please refresh the page and try again.",
            expect.objectContaining({ icon: undefined }),
        );
    });

    it("emits both captureMessage and captureException when explicit non-empty message is provided", () => {
        const error = new Error("Direct upload failed");
        handleError(error, "Upload failed");

        expect(captureMessage).toHaveBeenCalledTimes(1);
        expect(captureMessage).toHaveBeenCalledWith("Upload failed");
        expect(captureException).toHaveBeenCalledTimes(1);
        expect(captureException).toHaveBeenCalledWith(error);

        expect(toastErrorMock).toHaveBeenCalledWith(
            "Error in Sway. Upload failed",
            expect.objectContaining({ icon: undefined }),
        );
    });

    it("skips captureMessage and emits captureException when message contains only whitespace", () => {
        const error = new Error("Network glitch");
        handleError(error, "   ");

        expect(captureException).toHaveBeenCalledTimes(1);
        expect(captureException).toHaveBeenCalledWith(error);
        expect(captureMessage).not.toHaveBeenCalled();

        expect(toastErrorMock).toHaveBeenCalledWith("Error in Sway.    ", expect.objectContaining({ icon: undefined }));
    });

    it("emits captureMessage and skips captureException when error is undefined but message is provided", () => {
        handleError(undefined, "Explicit notice");

        expect(captureMessage).toHaveBeenCalledTimes(1);
        expect(captureMessage).toHaveBeenCalledWith("Explicit notice");
        expect(captureException).not.toHaveBeenCalled();

        expect(toastErrorMock).toHaveBeenCalledWith(
            "Error in Sway. Explicit notice",
            expect.objectContaining({ icon: undefined }),
        );
    });

    it("intercepts aborted operations without calling Sentry and displays an info toast", () => {
        const abortError = new Error("The operation was aborted.");
        handleError(abortError);

        expect(captureMessage).not.toHaveBeenCalled();
        expect(captureException).not.toHaveBeenCalled();
        expect(toastMock).toHaveBeenCalledWith("Cancelled", expect.objectContaining({ icon: "💡" }));
        expect(toastErrorMock).not.toHaveBeenCalled();
    });

    it("skips Sentry calls when neither IS_PRODUCTION nor IS_MOBILE_PHONE is active", () => {
        mockIsProduction = false;
        mockIsMobilePhone = false;

        const error = new Error("Local test error");
        handleError(error, "Local error message");

        expect(captureMessage).not.toHaveBeenCalled();
        expect(captureException).not.toHaveBeenCalled();
        expect(toastErrorMock).toHaveBeenCalledWith(
            "Error in Sway. Local error message",
            expect.objectContaining({ icon: undefined }),
        );
    });

    it("emits Sentry telemetry on mobile devices when IS_MOBILE_PHONE is true", () => {
        mockIsProduction = false;
        mockIsMobilePhone = true;

        const error = new Error("Mobile network issue");
        handleError(error);

        expect(captureException).toHaveBeenCalledTimes(1);
        expect(captureException).toHaveBeenCalledWith(error);
        expect(captureMessage).not.toHaveBeenCalled();
    });
});
