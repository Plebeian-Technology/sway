import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: jest.fn(),
        delete: jest.fn(),
        get: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("expo-document-picker", () => ({ getDocumentAsync: jest.fn() }));

import ClaimedAffiliationsSection from "../../../../src/components/admin/billCreator/ClaimedAffiliationsSection";
import PositionsTab from "../../../../src/screens/admin/billCreator/tabs/PositionsTab";

const claimed = {
    position: 3,
    phrase: "I speak for the Block Association.",
    role: "Chair",
    sender: "Pat Doe",
    org_name: "Block Association",
};

const tabData = (overrides: Record<string, unknown> = {}, claimedAffiliations: unknown[] = [claimed]) => ({
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
    testimony_claimed_affiliations: claimedAffiliations,
    ...overrides,
});

const renderSection = (data: Record<string, unknown>) => {
    const refresh = jest.fn(async () => {});
    render(<ClaimedAffiliationsSection billId={42} data={data} refresh={refresh} />);
    return { refresh };
};

const card = "admin-claimed-affiliation-3";

const writeSummary = (text: string) => {
    fireEvent.press(screen.getByTestId(`${card}-edit`));
    fireEvent.changeText(screen.getByTestId(`${card}-edit-summary`), text);
};

const refusal = (details: Record<string, unknown>) =>
    new ApiRequestError("validation_failed", "Validation failed.", details, 422);

// @lat: [[mobile-bill-creator#Sections#The claimed affiliations section]]
describe("ClaimedAffiliationsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
    });

    it("renders nothing when the bill has no claimed affiliations", () => {
        renderSection(tabData({}, []));

        expect(screen.queryByTestId("admin-claimed-affiliations")).toBeNull();
    });

    it("renders nothing when the prop is absent", () => {
        renderSection(tabData({ testimony_claimed_affiliations: undefined }));

        expect(screen.queryByTestId("admin-claimed-affiliations")).toBeNull();
    });

    it("skips a claim that carries no phrase, role or sender", () => {
        renderSection(tabData({}, [{ ...claimed, phrase: null, role: null, sender: null }]));

        expect(screen.queryByTestId(card)).toBeNull();
    });

    it("shows the name, the not-verified stamp, the evidence and the caution", () => {
        renderSection(tabData());

        expect(screen.getByTestId(`${card}-name`)).toHaveTextContent("Maybe: Block Association");
        expect(screen.getByText("CLAIMED, NOT VERIFIED")).toBeTruthy();
        expect(screen.getByText("I speak for the Block Association.")).toBeTruthy();
        expect(screen.getByText("Chair")).toBeTruthy();
        expect(screen.getByText("Pat Doe")).toBeTruthy();
        expect(
            screen.getByText("The sender said this. Nothing has confirmed it. Approve only if you know it is true."),
        ).toBeTruthy();
        expect(screen.getByTestId(`${card}-stance`)).toHaveTextContent("Support");
        expect(screen.getByTestId(`${card}-summary`)).toHaveTextContent("No summary yet — press Edit to add one.");
    });

    it("leaves out the evidence rows the claim does not carry", () => {
        renderSection(tabData({}, [{ ...claimed, role: null, sender: null }]));

        expect(screen.queryByText("Role claimed")).toBeNull();
        expect(screen.queryByText("Sender")).toBeNull();
        expect(screen.getByText("Phrase")).toBeTruthy();
    });

    it("clips a long phrase until the operator shows the whole phrase", () => {
        const phrase = "x".repeat(161);
        renderSection(tabData({}, [{ ...claimed, phrase }]));

        expect(screen.getByText(phrase).props.numberOfLines).toBe(2);
        fireEvent.press(screen.getByText("Show the whole phrase"));
        expect(screen.getByText(phrase).props.numberOfLines).toBeUndefined();
        fireEvent.press(screen.getByText("Show less"));
        expect(screen.getByText(phrase).props.numberOfLines).toBe(2);
    });

    it("offers no disclosure for a phrase of 160 characters or fewer", () => {
        renderSection(tabData({}, [{ ...claimed, phrase: "y".repeat(160) }]));

        expect(screen.queryByText("Show the whole phrase")).toBeNull();
    });

    it("keeps Approve off until a summary is written", () => {
        renderSection(tabData());

        expect(screen.getByTestId(`${card}-approve`)).toBeDisabled();
        writeSummary("   ");
        expect(screen.getByTestId(`${card}-approve`)).toBeDisabled();
        fireEvent.changeText(screen.getByTestId(`${card}-edit-summary`), "Backs the bill.");
        expect(screen.getByTestId(`${card}-approve`)).toBeEnabled();
    });

    it("approves with the claimed affiliation position and no override, then reloads", async () => {
        const { refresh } = renderSection(tabData());
        writeSummary("Backs the bill.");

        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/approve_org_position", {
                org_name: "Block Association",
                support: "support",
                summary: "Backs the bill.",
                claimed_affiliation_position: 3,
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("sends the edited name and position", async () => {
        renderSection(tabData());
        writeSummary("Fights the bill.");
        fireEvent.changeText(screen.getByTestId(`${card}-edit-name`), "Block Assoc.");
        fireEvent.press(screen.getByTestId(`${card}-edit-stance-oppose`));

        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith(
                "/bills/42/approve_org_position",
                expect.objectContaining({ org_name: "Block Assoc.", support: "oppose" }),
            ),
        );
    });

    it("seeds an empty name when the claim names no organization", async () => {
        renderSection(tabData({}, [{ ...claimed, org_name: null }]));

        expect(screen.getByTestId(`${card}-name`)).toHaveTextContent("Maybe:");
        writeSummary("Backs the bill.");
        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith(
                "/bills/42/approve_org_position",
                expect.objectContaining({ org_name: "" }),
            ),
        );
    });

    it("keeps typed edits when the operator closes the editor", () => {
        renderSection(tabData());
        writeSummary("Backs the bill.");

        fireEvent.press(screen.getByTestId(`${card}-edit-cancel`));

        expect(screen.queryByTestId(`${card}-edit-summary`)).toBeNull();
        expect(screen.getByTestId(`${card}-summary`)).toHaveTextContent("Backs the bill.");
    });

    it("toggles the editor with the Edit button", () => {
        renderSection(tabData());

        fireEvent.press(screen.getByTestId(`${card}-edit`));
        expect(screen.getByTestId(`${card}-edit-summary`)).toBeTruthy();
        fireEvent.press(screen.getByTestId(`${card}-edit`));
        expect(screen.queryByTestId(`${card}-edit-summary`)).toBeNull();
    });

    it("drops the card on Reject without sending a request", () => {
        renderSection(tabData());

        fireEvent.press(screen.getByTestId(`${card}-reject`));

        expect(screen.queryByTestId(card)).toBeNull();
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("shows the server's reason when an approval is refused", async () => {
        mockApiPost.mockRejectedValue(refusal({ org_position: "This draft list has changed." }));
        const { refresh } = renderSection(tabData());
        writeSummary("Backs the bill.");

        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() =>
            expect(screen.getByTestId(`${card}-error`)).toHaveTextContent("This draft list has changed."),
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("falls back to the server's message when the refusal names no reason", async () => {
        mockApiPost.mockRejectedValue(new ApiRequestError("server_error", "Something broke.", undefined, 500));
        renderSection(tabData());
        writeSummary("Backs the bill.");

        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() => expect(screen.getByTestId(`${card}-error`)).toHaveTextContent("Something broke."));
    });

    it("offers to approve a private individual anyway and resends with the override", async () => {
        mockApiPost.mockRejectedValueOnce(
            refusal({ org_position: "Reads Block Association as a person.", private_individual_refusal: true }),
        );
        const { refresh } = renderSection(tabData());
        writeSummary("Backs the bill.");

        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() => expect(screen.getByTestId(`${card}-override`)).toBeTruthy());
        expect(screen.getByTestId(`${card}-override`)).toHaveTextContent(
            /^Approve anyway\?Reads Block Association as a person\. Approving publishes this name as a followable organization\./,
        );
        fireEvent.press(screen.getByTestId(`${card}-override-confirm`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenLastCalledWith("/bills/42/approve_org_position", {
                org_name: "Block Association",
                support: "support",
                summary: "Backs the bill.",
                claimed_affiliation_position: 3,
                override_private_individual: true,
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("closes the private-individual panel on Cancel and keeps the reason on the card", async () => {
        mockApiPost.mockRejectedValueOnce(
            refusal({ org_position: "Reads Block Association as a person.", private_individual_refusal: true }),
        );
        renderSection(tabData());
        writeSummary("Backs the bill.");
        fireEvent.press(screen.getByTestId(`${card}-approve`));
        await waitFor(() => expect(screen.getByTestId(`${card}-override`)).toBeTruthy());

        fireEvent.press(screen.getByTestId(`${card}-override-cancel`));

        expect(screen.queryByTestId(`${card}-override`)).toBeNull();
        expect(screen.getByTestId(`${card}-error`)).toHaveTextContent("Reads Block Association as a person.");
    });

    it("shows a refusal that survives the override instead of asking again", async () => {
        mockApiPost.mockRejectedValue(
            refusal({ org_position: "Reads Block Association as a person.", private_individual_refusal: true }),
        );
        renderSection(tabData());
        writeSummary("Backs the bill.");
        fireEvent.press(screen.getByTestId(`${card}-approve`));
        await waitFor(() => expect(screen.getByTestId(`${card}-override`)).toBeTruthy());

        fireEvent.press(screen.getByTestId(`${card}-override-confirm`));

        await waitFor(() =>
            expect(screen.getByTestId(`${card}-error`)).toHaveTextContent("Reads Block Association as a person."),
        );
        expect(screen.queryByTestId(`${card}-override`)).toBeNull();
    });

    it.each([
        ["the bill has no testimony", { bill_llm_provisioning: { has_testimony: false, draft_org_positions: [] } }, {}],
        [
            "a summary run is generating",
            {
                bill_llm_provisioning: {
                    has_testimony: true,
                    generation_status: "generating",
                    draft_org_positions: [],
                },
            },
            {},
        ],
        [
            "a clean-testimony run is active",
            {},
            { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 42 } },
        ],
        [
            "testimony left out is unacknowledged",
            {},
            { testimony_coverage: { coverage_gap: true, acknowledged: false } },
        ],
    ])("keeps Approve off while %s", (_label, billOverrides, overrides) => {
        const base = tabData(overrides);
        renderSection({ ...base, bill: { ...base.bill, ...billOverrides } });
        writeSummary("Backs the bill.");

        expect(screen.getByTestId(`${card}-approve`)).toBeDisabled();
    });

    it("keeps Approve on when the left-out testimony is acknowledged", () => {
        renderSection(tabData({ testimony_coverage: { coverage_gap: true, acknowledged: true } }));
        writeSummary("Backs the bill.");

        expect(screen.getByTestId(`${card}-approve`)).toBeEnabled();
    });

    it("renders on the Positions tab between the drafts and the organizations", () => {
        render(<PositionsTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-draft-positions")).toBeTruthy();
        expect(screen.getByTestId("admin-claimed-affiliations")).toBeTruthy();
        expect(screen.getByTestId("admin-organizations")).toBeTruthy();
    });
});
