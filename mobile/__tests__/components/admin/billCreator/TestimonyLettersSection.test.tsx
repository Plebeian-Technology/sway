import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPatch = jest.fn();
const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: jest.fn(),
        patch: (...args: unknown[]) => mockApiPatch(...args),
        delete: jest.fn(),
        get: (...args: unknown[]) => mockApiGet(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("expo-document-picker", () => ({ getDocumentAsync: jest.fn() }));

import TestimonyLettersSection from "../../../../src/components/admin/billCreator/TestimonyLettersSection";
import PositionsTab from "../../../../src/screens/admin/billCreator/tabs/PositionsTab";

const letters = [
    { position: 3, label: "Constituent Letter #1", stance: "support", body_text: "I back this bill." },
    { position: 5, label: "Constituent Letter #2", stance: "oppose", body_text: "I am against it." },
];

const tabData = (counts: Record<string, number> = { total: 2, support: 1, oppose: 1, neutral: 0 }) => ({
    bill: {
        id: 42,
        external_id: "25-0001",
        title: "A bill",
        organizations: [],
        bill_llm_provisioning: {
            generation_status: "completed",
            has_testimony: true,
            reclaimable: false,
            draft_org_positions: [],
        },
        bill_pipeline_refresh: null,
    },
    organizations: [],
    tab_key: "positions",
    active_legislation_pipeline_run: null,
    testimony_coverage: null,
    public_testimony_counts: counts,
});

const renderSection = (data: Record<string, unknown> = tabData()) => {
    const refresh = jest.fn(async () => {});
    render(<TestimonyLettersSection billId={42} data={data} refresh={refresh} />);
    return { refresh };
};

const openLetters = async () => {
    fireEvent.press(screen.getByTestId("admin-testimony-letters-browse"));
    await screen.findByTestId("testimony-letter-3");
};

// @lat: [[mobile-bill-creator#Sections#The testimony section#Overriding a letter's stance]]
describe("TestimonyLettersSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPatch.mockResolvedValue({});
        mockApiGet.mockResolvedValue(letters);
    });

    it("renders nothing when the bill has no public testimony", () => {
        renderSection(tabData({ total: 0, support: 0, oppose: 0, neutral: 0 }));

        expect(screen.queryByTestId("admin-testimony-letters")).toBeNull();
    });

    it("loads the letters from the public letters endpoint when opened", async () => {
        renderSection();

        expect(mockApiGet).not.toHaveBeenCalled();
        await openLetters();

        expect(mockApiGet).toHaveBeenCalledWith("/bills/42/public_testimony_letters", expect.anything());
    });

    it("changing a letter's stance patches its position and stance and reloads the letters and the tab", async () => {
        const { refresh } = renderSection();
        await openLetters();

        fireEvent.press(screen.getByTestId("testimony-letter-3-set-oppose"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bills/42/testimony_letter_stance", {
                position: 3,
                stance: "oppose",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalled());
        expect(mockApiGet).toHaveBeenCalledTimes(2);
    });

    it("pressing the stance a letter already has sends nothing", async () => {
        renderSection();
        await openLetters();

        fireEvent.press(screen.getByTestId("testimony-letter-3-set-support"));

        expect(mockApiPatch).not.toHaveBeenCalled();
    });

    it("Remove excludes the letter", async () => {
        renderSection();
        await openLetters();

        fireEvent.press(screen.getByTestId("testimony-letter-5-remove"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bills/42/testimony_letter_stance", {
                position: 5,
                excluded: true,
            }),
        );
    });

    it("shows a refusal in the letter list", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { testimony_letter_stance: "Testimony letter not found." },
                422,
            ),
        );
        const { refresh } = renderSection();
        await openLetters();

        fireEvent.press(screen.getByTestId("testimony-letter-3-set-neutral"));

        expect(await screen.findByTestId("browse-testimony-sheet-edit-error")).toHaveTextContent(
            "Testimony letter not found.",
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("closes the letter list when the letter count drops to zero, so it stays closed when letters return", async () => {
        const refresh = jest.fn(async () => {});
        const { rerender } = render(<TestimonyLettersSection billId={42} data={tabData()} refresh={refresh} />);
        await openLetters();

        rerender(
            <TestimonyLettersSection
                billId={42}
                data={tabData({ total: 0, support: 0, oppose: 0, neutral: 0 })}
                refresh={refresh}
            />,
        );
        rerender(<TestimonyLettersSection billId={42} data={tabData()} refresh={refresh} />);

        expect(screen.getByTestId("admin-testimony-letters")).toBeTruthy();
        expect(screen.queryByTestId("browse-testimony-sheet")).toBeNull();
    });

    it("sits on the Positions tab", () => {
        render(<PositionsTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-testimony-letters")).toBeTruthy();
    });
});
