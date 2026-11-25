import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: jest.fn(),
        patch: (...args: unknown[]) => mockApiPatch(...args),
        delete: jest.fn(),
        get: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("expo-document-picker", () => ({ getDocumentAsync: jest.fn() }));

import SupplementalTestimonySection from "../../../../src/components/admin/billCreator/SupplementalTestimonySection";
import PositionsTab from "../../../../src/screens/admin/billCreator/tabs/PositionsTab";

const testimonyDraft = { org_name: "Block Association", stance: "support", summary: "Backs it" };
const newsDraft = { org_name: "Daily Paper", stance: "oppose", summary: "Against it", bill_news_article_id: 7 };

const tabData = (supplemental: string | null, drafts: unknown[] = []) => ({
    bill: {
        id: 42,
        external_id: "25-0001",
        title: "A bill",
        organizations: [],
        bill_llm_provisioning: {
            generation_status: "completed",
            has_testimony: true,
            reclaimable: false,
            supplemental_testimony: supplemental,
            draft_org_positions: drafts,
        },
        bill_pipeline_refresh: null,
    },
    organizations: [],
    tab_key: "positions",
    active_legislation_pipeline_run: null,
    testimony_coverage: null,
    public_testimony_counts: { total: 0, support: 0, oppose: 0, neutral: 0 },
});

const renderSection = (data: Record<string, unknown>) => {
    const refresh = jest.fn(async () => {});
    const view = render(<SupplementalTestimonySection billId={42} data={data} refresh={refresh} />);
    return { refresh, view };
};

const field = "admin-supplemental-testimony-input";
const save = "admin-supplemental-testimony-save";
const clear = "admin-supplemental-testimony-clear";

// @lat: [[mobile-bill-creator#Sections#The testimony section#Saving and clearing the supplemental testimony]]
describe("SupplementalTestimonySection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPatch.mockResolvedValue({});
    });

    it("shows the stored testimony, offers Clear and hides Save until the text changes", () => {
        renderSection(tabData("Stored testimony."));

        expect(screen.getByTestId(field).props.value).toBe("Stored testimony.");
        expect(screen.getByTestId(clear)).toBeTruthy();
        expect(screen.queryByTestId(save)).toBeNull();
    });

    it("offers no Clear when nothing is stored", () => {
        renderSection(tabData(null));

        expect(screen.queryByTestId(clear)).toBeNull();
    });

    it("saving patches the supplemental testimony and reloads the tab", async () => {
        const { refresh } = renderSection(tabData(null));

        fireEvent.changeText(screen.getByTestId(field), "New testimony.");
        fireEvent.press(screen.getByTestId(save));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bills/42/supplemental_testimony", {
                supplemental_testimony: "New testimony.",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalled());
    });

    it("clearing sends clear_supplemental_testimony and reloads the tab", async () => {
        const { refresh } = renderSection(tabData("Stored testimony."));

        fireEvent.press(screen.getByTestId(clear));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bills/42/supplemental_testimony", {
                clear_supplemental_testimony: true,
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalled());
    });

    it("asks before a save replaces the testimony that draft positions were written from", async () => {
        renderSection(tabData("Stored testimony.", [testimonyDraft, newsDraft]));

        fireEvent.changeText(screen.getByTestId(field), "Different testimony.");
        fireEvent.press(screen.getByTestId(save));

        expect(mockApiPatch).not.toHaveBeenCalled();
        expect(screen.getByText("Save and block these positions?")).toBeTruthy();
        expect(screen.getByTestId("admin-supplemental-testimony-confirm-text").props.children).toBe(
            "Saving replaces the testimony the 1 draft position on this bill was written from, so it can no " +
                "longer be approved. Regenerate or reject them instead of pasting the old testimony back.",
        );

        fireEvent.press(screen.getByTestId("admin-supplemental-testimony-confirm"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bills/42/supplemental_testimony", {
                supplemental_testimony: "Different testimony.",
            }),
        );
    });

    it("saves without asking when the new text keeps the stored testimony", async () => {
        renderSection(tabData("Stored testimony.", [testimonyDraft]));

        fireEvent.changeText(screen.getByTestId(field), "Stored testimony. And more.");
        fireEvent.press(screen.getByTestId(save));

        await waitFor(() => expect(mockApiPatch).toHaveBeenCalled());
    });

    it("saves without asking when every draft came from the news", async () => {
        renderSection(tabData("Stored testimony.", [newsDraft]));

        fireEvent.changeText(screen.getByTestId(field), "Different testimony.");
        fireEvent.press(screen.getByTestId(save));

        await waitFor(() => expect(mockApiPatch).toHaveBeenCalled());
    });

    it("asks before clearing testimony that draft positions were written from, and Cancel sends nothing", () => {
        renderSection(tabData("Stored testimony.", [testimonyDraft, testimonyDraft]));

        fireEvent.press(screen.getByTestId(clear));

        expect(screen.getByText("Clear the testimony and block these positions?")).toBeTruthy();
        expect(screen.getByTestId("admin-supplemental-testimony-confirm-text").props.children).toBe(
            "Clearing removes the testimony the 2 draft positions on this bill were written from, so they can " +
                "no longer be approved. Pasting the testimony back does not restore them — regenerate or reject " +
                "them instead.",
        );

        fireEvent.press(screen.getByTestId("admin-supplemental-testimony-cancel"));

        expect(screen.queryByTestId("admin-supplemental-testimony-confirm")).toBeNull();
        expect(mockApiPatch).not.toHaveBeenCalled();
    });

    it("takes a newer server value while nothing is unsaved, and keeps typed text otherwise", () => {
        const refresh = jest.fn(async () => {});
        const { rerender } = render(
            <SupplementalTestimonySection billId={42} data={tabData(null)} refresh={refresh} />,
        );

        rerender(<SupplementalTestimonySection billId={42} data={tabData("Arrived.")} refresh={refresh} />);
        expect(screen.getByTestId(field).props.value).toBe("Arrived.");

        fireEvent.changeText(screen.getByTestId(field), "Typed.");
        rerender(<SupplementalTestimonySection billId={42} data={tabData("Arrived again.")} refresh={refresh} />);
        expect(screen.getByTestId(field).props.value).toBe("Typed.");
    });

    it("shows a refused save with the server's message and keeps the text", async () => {
        mockApiPatch.mockRejectedValue(new ApiRequestError("forbidden", "Admins only.", undefined, 403));
        const { refresh } = renderSection(tabData(null));

        fireEvent.changeText(screen.getByTestId(field), "New testimony.");
        fireEvent.press(screen.getByTestId(save));

        expect(await screen.findByTestId("admin-supplemental-testimony-error")).toHaveTextContent(
            "Could not save the supplemental testimony — it is not on this bill yet. Admins only.",
        );
        expect(screen.getByTestId(field).props.value).toBe("New testimony.");
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows a refused clear with the server's message", async () => {
        mockApiPatch.mockRejectedValue(new ApiRequestError("forbidden", "Admins only.", undefined, 403));
        renderSection(tabData("Stored testimony."));

        fireEvent.press(screen.getByTestId(clear));

        expect(await screen.findByTestId("admin-supplemental-testimony-error")).toHaveTextContent(
            "Could not clear the supplemental testimony — it is still on this bill. Admins only.",
        );
    });

    it("sits on the Positions tab above the draft positions", () => {
        render(<PositionsTab billId={42} data={tabData(null)} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-supplemental-testimony")).toBeTruthy();
        expect(screen.getByTestId("admin-draft-positions")).toBeTruthy();
    });
});
