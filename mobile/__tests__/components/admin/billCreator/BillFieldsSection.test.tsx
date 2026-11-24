import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

const baltimore = {
    id: 7,
    name: "baltimore-maryland-united_states",
    default_bill_chamber: "council",
    bill_chambers: ["council"],
};
const maryland = {
    id: 8,
    name: "maryland-maryland-united_states",
    default_bill_chamber: null,
    bill_chambers: ["house", "senate"],
};
let mockBootstrapLocale: Record<string, unknown> | null = baltimore;
jest.mock("../../../../src/state/BootstrapContext", () => ({
    useBootstrap: () => ({
        bootstrap: { locale: mockBootstrapLocale, sway_locales: [baltimore, maryland] },
    }),
}));

import BillFieldsSection, { type CreatorBill } from "../../../../src/components/admin/billCreator/BillFieldsSection";

const newBill: CreatorBill = {
    id: null,
    external_id: null,
    external_version: null,
    title: null,
    link: null,
    chamber: null,
    status: null,
    active: null,
    introduced_date_time_utc: null,
    house_vote_date_time_utc: null,
    senate_vote_date_time_utc: null,
    legislator_id: null,
    sway_locale_id: null,
};

const savedBill: CreatorBill = {
    ...newBill,
    id: 42,
    external_id: "25-0042",
    external_version: "0",
    title: "Rent Stabilization",
    link: "https://baltimore.legistar.com/25-0042",
    chamber: "council",
    status: "committee",
    active: true,
    introduced_date_time_utc: "2026-01-05T00:00:00.000Z",
    legislator_id: 3,
    sway_locale_id: 7,
    vote: { house_roll_call_vote_number: 12, senate_roll_call_vote_number: null },
};

const legislators = [
    { id: 3, first_name: "zeke", last_name: "cohen", district: { region_code: "MD", number: 1 } },
    { id: 4, first_name: "odette", last_name: "ramos", district: { region_code: "MD", number: 14 } },
];

const typeInto = (name: string, text: string) =>
    fireEvent.changeText(screen.getByTestId(`admin-bill-fields-${name}-input`), text);

const choose = (name: string, value: string | number) => {
    fireEvent.press(screen.getByTestId(`admin-bill-fields-${name}-toggle`));
    fireEvent.press(screen.getByTestId(`admin-bill-fields-${name}-option-${value}`));
};

// @lat: [[mobile-bill-creator#Sections#The bill fields section]]
describe("BillFieldsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockBootstrapLocale = baltimore;
    });

    it("asks for a locale before sending anything", () => {
        mockBootstrapLocale = null;
        render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={jest.fn()} />);

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        expect(screen.getByText("Please select a locale before saving.")).toBeTruthy();
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("asks for the chamber before sending anything", () => {
        render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={jest.fn()} />);
        choose("sway_locale_id", 8);

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        expect(screen.getByText("Please select the bill chamber before saving.")).toBeTruthy();
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("asks for the sponsor before sending anything", () => {
        render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={jest.fn()} />);

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        expect(screen.getByText("Please select the bill sponsor before saving.")).toBeTruthy();
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("refuses a date that is not written as YYYY-MM-DD", () => {
        render(<BillFieldsSection billId={42} bill={savedBill} legislators={legislators} onSaved={jest.fn()} />);
        typeInto("introduced_date_time_utc", "Jan 5");

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        expect(screen.getByText("Enter the date as YYYY-MM-DD.")).toBeTruthy();
        expect(mockApiPatch).not.toHaveBeenCalled();
    });

    it("keeps the chamber fixed when the locale has one chamber", () => {
        render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={jest.fn()} />);

        expect(screen.getByTestId("admin-bill-fields-chamber-toggle").props.accessibilityState).toEqual(
            expect.objectContaining({ disabled: true }),
        );
        expect(screen.getByText("council")).toBeTruthy();
    });

    it("creates a bill with the locale, news usage, status, chamber and sponsor, then shows it", async () => {
        const onSaved = jest.fn();
        mockApiPost.mockResolvedValue({ ...savedBill, title: "Rent Stabilization Act" });
        render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={onSaved} />);
        typeInto("external_id", "25-0042");
        typeInto("title", "Rent Stabilization");
        typeInto("link", "https://baltimore.legistar.com/25-0042");
        typeInto("introduced_date_time_utc", "2026-01-05");
        choose("legislator_id", 3);

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith(
                "/bills",
                expect.objectContaining({
                    sway_locale_id: 7,
                    news_usage: "none",
                    status: "committee",
                    chamber: "council",
                    legislator_id: 3,
                    external_id: "25-0042",
                    title: "Rent Stabilization",
                    active: true,
                    introduced_date_time_utc: "2026-01-05T00:00:00.000Z",
                }),
            ),
        );
        expect(await screen.findByText("Bill saved.")).toBeTruthy();
        expect(screen.getByTestId("admin-bill-fields-title-input").props.value).toBe("Rent Stabilization Act");
        expect(onSaved).toHaveBeenCalledWith(expect.objectContaining({ id: 42 }));
    });

    it("updates a saved bill with its current fields", async () => {
        mockApiPatch.mockResolvedValue({ ...savedBill, status: "passed" });
        render(<BillFieldsSection billId={42} bill={savedBill} legislators={legislators} onSaved={jest.fn()} />);
        choose("status", "passed");

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith(
                "/bills/42",
                expect.objectContaining({
                    sway_locale_id: 7,
                    news_usage: "none",
                    status: "passed",
                    chamber: "council",
                    legislator_id: 3,
                    house_roll_call_vote_number: "12",
                }),
            ),
        );
        expect(await screen.findByText("Bill saved.")).toBeTruthy();
        expect(screen.getByText("Passed")).toBeTruthy();
    });

    it("shows the server's field errors under their fields", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError("validation_failed", "Validation failed.", { title: ["Title can't be blank"] }, 422),
        );
        render(<BillFieldsSection billId={42} bill={savedBill} legislators={legislators} onSaved={jest.fn()} />);
        typeInto("title", "");

        fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

        expect(await screen.findByText("Title can't be blank")).toBeTruthy();
        expect(screen.getByText("Validation failed.")).toBeTruthy();
        expect(screen.queryByText("Bill saved.")).toBeNull();
    });

    // @lat: [[mobile-bill-creator#Sections#The bill fields section#The summary field]]
    describe("the summary field", () => {
        it("creates a new bill with its summary and succeeds", async () => {
            const onSaved = jest.fn();
            mockApiPost.mockResolvedValue({ ...savedBill, summary: "Caps yearly rent increases." });
            render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={onSaved} />);
            typeInto("external_id", "25-0042");
            typeInto("title", "Rent Stabilization");
            choose("legislator_id", 3);
            typeInto("summary", "Caps yearly rent increases.");

            fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith(
                    "/bills",
                    expect.objectContaining({ summary: "Caps yearly rent increases.", news_usage: "none" }),
                ),
            );
            expect(await screen.findByText("Bill saved.")).toBeTruthy();
            expect(onSaved).toHaveBeenCalledWith(expect.objectContaining({ id: 42 }));
        });

        it("starts from the saved summary and publishes an edit with news usage none", async () => {
            mockApiPatch.mockResolvedValue({ ...savedBill, summary: "Caps rent increases at 3%." });
            render(
                <BillFieldsSection
                    billId={42}
                    bill={{ ...savedBill, summary: "Caps rent increases." }}
                    legislators={legislators}
                    onSaved={jest.fn()}
                />,
            );
            expect(screen.getByTestId("admin-bill-fields-summary-input").props.value).toBe("Caps rent increases.");
            typeInto("summary", "Caps rent increases at 3%.");

            fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

            await waitFor(() =>
                expect(mockApiPatch).toHaveBeenCalledWith(
                    "/bills/42",
                    expect.objectContaining({ summary: "Caps rent increases at 3%.", news_usage: "none" }),
                ),
            );
            expect(await screen.findByText("Bill saved.")).toBeTruthy();
        });

        it("shows each reason the server gives for refusing the summary", async () => {
            mockApiPatch.mockRejectedValue(
                new ApiRequestError(
                    "validation_failed",
                    "Manual summary publication failed validation.",
                    {
                        status: "news_usage_mismatch",
                        errors: ["The summary links to news but declares no news use.", "Remove the link."],
                    },
                    422,
                ),
            );
            render(<BillFieldsSection billId={42} bill={savedBill} legislators={legislators} onSaved={jest.fn()} />);
            typeInto("summary", "Read [the Banner](https://thebaltimorebanner.com/rent).");

            fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

            expect(await screen.findByText("The summary links to news but declares no news use.")).toBeTruthy();
            expect(screen.getByText("Remove the link.")).toBeTruthy();
            expect(screen.getByText("Manual summary publication failed validation.")).toBeTruthy();
            expect(screen.queryByTestId("admin-bill-fields-status-error")).toBeNull();
            expect(screen.queryByText("Bill saved.")).toBeNull();
        });

        it("shows the server's blank-summary error under the summary", async () => {
            mockApiPost.mockRejectedValue(
                new ApiRequestError(
                    "validation_failed",
                    "Validation failed.",
                    { summary: ["Summary can't be blank"] },
                    422,
                ),
            );
            render(<BillFieldsSection billId={null} bill={newBill} legislators={legislators} onSaved={jest.fn()} />);
            choose("legislator_id", 3);

            fireEvent.press(screen.getByTestId("admin-bill-fields-save"));

            expect(await screen.findByTestId("admin-bill-fields-summary-error")).toHaveTextContent(
                "Summary can't be blank",
            );
        });

        it("previews the summary as markdown", () => {
            render(<BillFieldsSection billId={42} bill={savedBill} legislators={legislators} onSaved={jest.fn()} />);
            typeInto("summary", "Caps **rent** increases.");

            expect(screen.getByTestId("admin-bill-fields-summary-preview")).toHaveTextContent("Caps rent increases.");
        });
    });
});
