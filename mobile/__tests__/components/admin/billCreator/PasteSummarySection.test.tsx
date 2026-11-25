import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
    },
}));

let mockIsOnline = true;
jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: mockIsOnline, isResolved: true }),
}));

import PasteSummarySection from "../../../../src/components/admin/billCreator/PasteSummarySection";
import SummaryTab from "../../../../src/screens/admin/billCreator/tabs/SummaryTab";

const SUMMARY_JSON = '{ "summary_markdown": "Short summary.", "categories": ["Housing"] }';

const renderSection = (billId: number | null = 42) => {
    const refresh = jest.fn(async () => {});
    render(<PasteSummarySection billId={billId} refresh={refresh} />);
    return { refresh };
};

const openAndType = (text: string) => {
    fireEvent.press(screen.getByTestId("admin-summary-paste-open"));
    fireEvent.changeText(screen.getByTestId("admin-summary-paste-input"), text);
};

// @lat: [[mobile-bill-creator#Sections#The paste summary section]]
describe("PasteSummarySection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockIsOnline = true;
        mockApiPost.mockResolvedValue({ bill: { id: 42 } });
    });

    it("renders under the Summary tab", () => {
        render(
            <SummaryTab
                billId={42}
                data={{ bill: { id: 42, external_id: null, title: null } }}
                refresh={jest.fn(async () => {})}
            />,
        );

        expect(screen.getByTestId("admin-summary-paste-open")).toHaveTextContent("Paste summary JSON");
    });

    it("opens a box with the web dialog's title, help text and placeholder", () => {
        renderSection();

        expect(screen.queryByTestId("admin-summary-paste-input")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-paste-open"));

        expect(screen.getByTestId("admin-summary-paste")).toHaveTextContent(/Paste bill summary JSON/);
        expect(screen.getByTestId("admin-summary-paste")).toHaveTextContent(
            /Paste a valid bill summary JSON payload to create a review draft\. The schema is shown below for reference\./,
        );
        expect(screen.getByTestId("admin-summary-paste-input").props.placeholder).toBe(
            '{ "summary_markdown": "...", "full_breakdown_markdown": "..." }',
        );
        expect(screen.getByTestId("admin-summary-paste-input").props.accessibilityLabel).toBe("Bill summary JSON");
    });

    it("keeps Validate & paste disabled until the box has text besides whitespace", () => {
        renderSection();
        fireEvent.press(screen.getByTestId("admin-summary-paste-open"));
        const submit = screen.getByTestId("admin-summary-paste-submit");

        expect(submit).toHaveTextContent("Validate & paste");
        expect(submit).toBeDisabled();
        fireEvent.changeText(screen.getByTestId("admin-summary-paste-input"), "  \n ");
        expect(submit).toBeDisabled();
        fireEvent.changeText(screen.getByTestId("admin-summary-paste-input"), SUMMARY_JSON);
        expect(submit).not.toBeDisabled();
    });

    it("posts the pasted text as summary_json, untrimmed, then clears the box and refreshes the tab", async () => {
        const { refresh } = renderSection();
        openAndType(`  ${SUMMARY_JSON}\n`);

        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));

        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(mockApiPost).toHaveBeenCalledWith("/bills/42/paste_summary", { summary_json: `  ${SUMMARY_JSON}\n` });
        expect(screen.queryByTestId("admin-summary-paste-input")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-paste-open"));
        expect(screen.getByTestId("admin-summary-paste-input").props.value).toBe("");
    });

    it("locks the box and both buttons while the request runs", async () => {
        let finish: (value: unknown) => void = () => {};
        mockApiPost.mockReturnValueOnce(new Promise((resolve) => (finish = resolve)));
        renderSection();
        openAndType(SUMMARY_JSON);

        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));

        await waitFor(() => expect(screen.getByTestId("admin-summary-paste-submit")).toBeDisabled());
        expect(screen.getByTestId("admin-summary-paste-input").props.editable).toBe(false);
        expect(screen.getByTestId("admin-summary-paste-cancel")).toBeDisabled();
        await act(async () => {
            finish({});
        });
        expect(screen.queryByTestId("admin-summary-paste-input")).toBeNull();
    });

    it("lists each rejected path with its message and keeps the text and the tab as they are", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Summary validation failed.",
                {
                    errors: [
                        { path: "/summary_markdown", message: "can't be blank" },
                        { path: "/categories/0", message: "is not a known category" },
                    ],
                },
                422,
            ),
        );
        const { refresh } = renderSection();
        openAndType(SUMMARY_JSON);

        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));

        expect(await screen.findByTestId("admin-summary-paste-error-0")).toHaveTextContent(
            "/summary_markdown can't be blank",
        );
        expect(screen.getByTestId("admin-summary-paste-error-1")).toHaveTextContent(
            "/categories/0 is not a known category",
        );
        expect(screen.getByTestId("admin-summary-paste-input").props.value).toBe(SUMMARY_JSON);
        expect(screen.getByTestId("admin-summary-paste-submit")).not.toBeDisabled();
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows the server's message when a refusal carries no path list", async () => {
        mockApiPost.mockRejectedValueOnce(new ApiRequestError("forbidden", "Admin access required.", undefined, 403));
        renderSection();
        openAndType(SUMMARY_JSON);

        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));

        expect(await screen.findByTestId("admin-summary-paste-failure")).toHaveTextContent("Admin access required.");
        expect(screen.queryByTestId("admin-summary-paste-error-0")).toBeNull();
    });

    it("clears the earlier rejection when the next paste is sent", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Summary validation failed.",
                { errors: [{ path: "/summary_markdown", message: "can't be blank" }] },
                422,
            ),
        );
        renderSection();
        openAndType(SUMMARY_JSON);
        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));
        await screen.findByTestId("admin-summary-paste-error-0");

        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));

        await waitFor(() => expect(screen.queryByTestId("admin-summary-paste-error-0")).toBeNull());
    });

    it("moves the cursor to the rejected key when its error is tapped, and to the top when the key is not found", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Summary validation failed.",
                {
                    errors: [
                        { path: "/categories", message: "is not a known category" },
                        { path: "/news_usage", message: "is required" },
                    ],
                },
                422,
            ),
        );
        renderSection();
        openAndType(SUMMARY_JSON);
        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));
        await screen.findByTestId("admin-summary-paste-error-0");

        fireEvent.press(screen.getByTestId("admin-summary-paste-error-0"));
        const offset = SUMMARY_JSON.indexOf('"categories"');
        expect(screen.getByTestId("admin-summary-paste-input").props.selection).toEqual({ start: offset, end: offset });

        fireEvent.press(screen.getByTestId("admin-summary-paste-error-1"));
        expect(screen.getByTestId("admin-summary-paste-input").props.selection).toEqual({ start: 0, end: 0 });
    });

    it("clears the text and the errors and closes the box on Cancel", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Summary validation failed.",
                { errors: [{ path: "/summary_markdown", message: "can't be blank" }] },
                422,
            ),
        );
        renderSection();
        openAndType(SUMMARY_JSON);
        fireEvent.press(screen.getByTestId("admin-summary-paste-submit"));
        await screen.findByTestId("admin-summary-paste-error-0");

        fireEvent.press(screen.getByTestId("admin-summary-paste-cancel"));

        expect(screen.queryByTestId("admin-summary-paste-input")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-paste-open"));
        expect(screen.getByTestId("admin-summary-paste-input").props.value).toBe("");
        expect(screen.queryByTestId("admin-summary-paste-error-0")).toBeNull();
        expect(mockApiPost).toHaveBeenCalledTimes(1);
    });

    it("shows the schema example under a Schema reference toggle", () => {
        renderSection();
        fireEvent.press(screen.getByTestId("admin-summary-paste-open"));

        expect(screen.queryByTestId("admin-summary-paste-schema-example")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-paste-schema-toggle"));

        expect(screen.getByTestId("admin-summary-paste-schema-example")).toHaveTextContent(/"summary_markdown"/);
        expect(screen.getByTestId("admin-summary-paste-schema-example")).toHaveTextContent(/"cited_section_keys"/);
    });

    it("tells the admin to save a new bill first", () => {
        renderSection(null);

        expect(screen.getByTestId("admin-summary-paste")).toHaveTextContent("Save the bill before pasting a summary.");
        expect(screen.queryByTestId("admin-summary-paste-open")).toBeNull();
    });
});
