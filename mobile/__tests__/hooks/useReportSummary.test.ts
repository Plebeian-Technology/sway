// @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
const mockPost = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { post: (...args: unknown[]) => mockPost(...args) },
}));

import { act, renderHook } from "@testing-library/react-native";

import { ApiRequestError, NetworkError, RateLimitedError, UnauthorizedError } from "../../src/api/errors";
import { useReportSummary } from "../../src/hooks/useReportSummary";

const submitReport = async (billId: number, details = "  The summary misstates the fee.  ") => {
    const { result } = renderHook(() => useReportSummary(billId));
    let outcome: string | undefined;
    await act(async () => {
        outcome = await result.current.submit("factual_inaccuracy", details);
    });
    return { outcome, result };
};

describe("useReportSummary", () => {
    beforeEach(() => {
        mockPost.mockReset();
        mockPost.mockResolvedValue({ id: 1 });
    });

    test("POSTs the nested report params, with trimmed details, to the bill's summary_reports route", async () => {
        const { outcome } = await submitReport(42);

        expect(mockPost).toHaveBeenCalledTimes(1);
        expect(mockPost).toHaveBeenCalledWith("/bills/42/summary_reports", {
            bill_summary_report: { reason: "factual_inaccuracy", details: "The summary misstates the fee." },
        });
        expect(outcome).toBe("submitted");
    });

    test("reports the submitting state while the request is in flight", async () => {
        let resolvePost: (value: unknown) => void = () => {};
        mockPost.mockReturnValueOnce(new Promise((resolve) => (resolvePost = resolve)));
        const { result } = renderHook(() => useReportSummary(7));
        expect(result.current.submitting).toBe(false);

        let pending: Promise<string> = Promise.resolve("");
        act(() => {
            pending = result.current.submit("other", "Something is wrong here.");
        });
        expect(result.current.submitting).toBe(true);

        await act(async () => {
            resolvePost({ id: 2 });
            await pending;
        });
        expect(result.current.submitting).toBe(false);
    });

    test("maps a 422 validation_failed to the duplicate outcome", async () => {
        mockPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "A report for this bill summary was already submitted recently. Thank you for your feedback.",
                undefined,
                422,
            ),
        );
        const { outcome, result } = await submitReport(42);

        expect(outcome).toBe("duplicate");
        expect(result.current.submitting).toBe(false);
    });

    test("maps a 429 rate_limited to the rate_limited outcome", async () => {
        mockPost.mockRejectedValueOnce(
            new RateLimitedError("rate_limited", "Too many attempts. Please try again shortly.", undefined, 429),
        );
        const { outcome } = await submitReport(42);

        expect(outcome).toBe("rate_limited");
    });

    test("maps a network error to the offline outcome", async () => {
        mockPost.mockRejectedValueOnce(new NetworkError("network_error", "Network request failed"));
        const { outcome } = await submitReport(42);

        expect(outcome).toBe("offline");
    });

    test.each([
        ["a 500", new ApiRequestError("http_500", "HTTP 500", undefined, 500)],
        ["a 401", new UnauthorizedError("unauthorized", "Sign in again", undefined, 401)],
        ["an unexpected error", new Error("boom")],
    ])("maps %s to the failed outcome", async (_label, error) => {
        mockPost.mockRejectedValueOnce(error);
        const { outcome, result } = await submitReport(42);

        expect(outcome).toBe("failed");
        expect(result.current.submitting).toBe(false);
    });
});
