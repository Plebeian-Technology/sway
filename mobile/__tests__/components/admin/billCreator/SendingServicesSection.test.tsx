import React from "react";
import { Alert } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { patch: (...args: unknown[]) => mockApiPatch(...args) },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import SendingServicesSection from "../../../../src/components/admin/billCreator/SendingServicesSection";

const domainRow = (id: number, overrides: Record<string, unknown> = {}) => ({
    id,
    domain: `domain-${id}.example.com`,
    label: "none",
    sender_count: 12,
    machine_sent_letter_count: 30,
    letter_count: 40,
    bill_count: 2,
    ...overrides,
});

const renderSection = (domains: unknown[], total?: number, refresh = jest.fn(async () => {})) => {
    render(
        <SendingServicesSection
            billId={42}
            data={{ sending_service_domains: domains, sending_service_domains_total: total ?? domains.length }}
            refresh={refresh}
        />,
    );
    fireEvent.press(screen.getByTestId("admin-sending-services-toggle"));
    return { refresh };
};

const pressAlertButton = (alertSpy: jest.SpyInstance, text: string) => {
    const buttons = alertSpy.mock.calls[alertSpy.mock.calls.length - 1][2] as { text: string; onPress?: () => void }[];
    buttons.find((button) => button.text === text)?.onPress?.();
};

// @lat: [[mobile-bill-creator#Sections#The sending services section]]
describe("SendingServicesSection", () => {
    let alertSpy: jest.SpyInstance;

    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPatch.mockResolvedValue({});
        alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
    });

    afterEach(() => alertSpy.mockRestore());

    it("renders nothing inside until opened", () => {
        render(
            <SendingServicesSection
                billId={42}
                data={{ sending_service_domains: [domainRow(1)], sending_service_domains_total: 1 }}
                refresh={jest.fn()}
            />,
        );
        expect(screen.queryByTestId("admin-sending-service-1")).toBeNull();
    });

    it("says there are no domains when the list is empty", () => {
        renderSection([]);
        expect(screen.getByText("No sending-service domains yet.")).toBeTruthy();
        expect(screen.queryByTestId("admin-sending-services-search-input")).toBeNull();
    });

    it("shows a row's counts, machine-sent share and stamp", () => {
        renderSection([domainRow(1, { label: "proposed" })]);
        expect(screen.getByText("domain-1.example.com")).toBeTruthy();
        expect(screen.getByText("75%")).toBeTruthy();
        expect(screen.getByText("30 of 40 letters")).toBeTruthy();
        expect(screen.getByTestId("admin-sending-service-1-stamp").props.children).toBe("PROPOSED");
    });

    it("reads a domain with no letters as 0% of 0 letters and an unknown label as UNLABELED", () => {
        renderSection([domainRow(1, { letter_count: 0, machine_sent_letter_count: 0, label: "other" })]);
        expect(screen.getByText("0%")).toBeTruthy();
        expect(screen.getByText("0 of 0 letters")).toBeTruthy();
        expect(screen.getByTestId("admin-sending-service-1-stamp").props.children).toBe("UNLABELED");
    });

    it("uses the singular for exactly one letter", () => {
        renderSection([domainRow(1, { letter_count: 1, machine_sent_letter_count: 1 })]);
        expect(screen.getByText("1 of 1 letter")).toBeTruthy();
    });

    it("says how many domains the capped list leaves out", () => {
        renderSection([domainRow(1)], 1200);
        expect(screen.getByText("Showing the 1 domains with the most machine-sent letters, of 1,200.")).toBeTruthy();
    });

    it("pages five domains at a time", () => {
        renderSection([1, 2, 3, 4, 5, 6, 7].map((id) => domainRow(id)));
        expect(screen.getByText("Page 1 of 2")).toBeTruthy();
        expect(screen.getByTestId("admin-sending-service-5")).toBeTruthy();
        expect(screen.queryByTestId("admin-sending-service-6")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-sending-services-next"));
        expect(screen.getByText("Page 2 of 2")).toBeTruthy();
        expect(screen.getByTestId("admin-sending-service-6")).toBeTruthy();
        expect(screen.queryByTestId("admin-sending-service-1")).toBeNull();
    });

    it("filters by domain text and says when nothing matches", () => {
        renderSection([domainRow(1), domainRow(2)], 5);
        fireEvent.changeText(screen.getByTestId("admin-sending-services-search-input"), "DOMAIN-2");
        expect(screen.queryByTestId("admin-sending-service-1")).toBeNull();
        expect(screen.getByTestId("admin-sending-service-2")).toBeTruthy();
        fireEvent.changeText(screen.getByTestId("admin-sending-services-search-input"), "nope");
        expect(
            screen.getByText("No domains match this search among the 2 shown — 3 more are not loaded."),
        ).toBeTruthy();
    });

    it("says a search with no match plainly when the list is not capped", () => {
        renderSection([domainRow(1)]);
        fireEvent.changeText(screen.getByTestId("admin-sending-services-search-input"), "nope");
        expect(screen.getByText("No domains match this search.")).toBeTruthy();
    });

    it("offers Confirm and Not a sending service on an unconfirmed domain and Remove on a confirmed one", () => {
        renderSection([domainRow(1), domainRow(2, { label: "confirmed" })]);
        expect(screen.getByTestId("admin-sending-service-1-confirm")).toBeTruthy();
        expect(screen.getByTestId("admin-sending-service-1-not")).toBeTruthy();
        expect(screen.queryByTestId("admin-sending-service-1-remove")).toBeNull();
        expect(screen.getByTestId("admin-sending-service-2-remove")).toBeTruthy();
        expect(screen.queryByTestId("admin-sending-service-2-confirm")).toBeNull();
    });

    // @lat: [[mobile-bill-creator#Sections#The sending services section]]
    it("labels a domain confirmed with PATCH label and bill_id after the admin agrees, then refreshes", async () => {
        const { refresh } = renderSection([domainRow(7)]);
        fireEvent.press(screen.getByTestId("admin-sending-service-7-confirm"));

        expect(alertSpy.mock.calls[0][0]).toBe("Confirm domain-7.example.com as a sending service?");
        expect(mockApiPatch).not.toHaveBeenCalled();
        pressAlertButton(alertSpy, "Confirm");

        await waitFor(() => expect(refresh).toHaveBeenCalled());
        expect(mockApiPatch).toHaveBeenCalledWith("/sending_service_domains/7", { label: "confirmed", bill_id: 42 });
    });

    it("sends label none for Not a sending service", async () => {
        const { refresh } = renderSection([domainRow(7)]);
        fireEvent.press(screen.getByTestId("admin-sending-service-7-not"));
        expect(alertSpy.mock.calls[0][0]).toBe("Remove the sending-service label from domain-7.example.com?");
        pressAlertButton(alertSpy, "Remove the label");

        await waitFor(() => expect(refresh).toHaveBeenCalled());
        expect(mockApiPatch).toHaveBeenCalledWith("/sending_service_domains/7", { label: "none", bill_id: 42 });
    });

    it("sends label none for Remove this label", async () => {
        renderSection([domainRow(7, { label: "confirmed" })]);
        fireEvent.press(screen.getByTestId("admin-sending-service-7-remove"));
        pressAlertButton(alertSpy, "Remove the label");

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/sending_service_domains/7", { label: "none", bill_id: 42 }),
        );
    });

    it("sends nothing when the admin cancels", () => {
        renderSection([domainRow(7)]);
        fireEvent.press(screen.getByTestId("admin-sending-service-7-confirm"));
        pressAlertButton(alertSpy, "Cancel");
        expect(mockApiPatch).not.toHaveBeenCalled();
    });

    it("shows the server's sending_service reason under the row and does not refresh", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { sending_service: "Unknown label value" },
                422,
            ),
        );
        const { refresh } = renderSection([domainRow(7)]);
        fireEvent.press(screen.getByTestId("admin-sending-service-7-confirm"));
        pressAlertButton(alertSpy, "Confirm");

        expect((await screen.findByTestId("admin-sending-service-7-error")).props.children).toBe("Unknown label value");
        expect(refresh).not.toHaveBeenCalled();
    });

    it("disables a row's buttons while its request runs", async () => {
        let finish: (value: unknown) => void = () => {};
        mockApiPatch.mockReturnValue(new Promise((resolve) => (finish = resolve)));
        renderSection([domainRow(7)]);
        fireEvent.press(screen.getByTestId("admin-sending-service-7-confirm"));
        pressAlertButton(alertSpy, "Confirm");

        await waitFor(() =>
            expect(screen.getByTestId("admin-sending-service-7-not").props.accessibilityState?.disabled).toBe(true),
        );
        await act(async () => finish({}));
    });
});
