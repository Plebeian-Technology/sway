import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        get: (...args: unknown[]) => mockApiGet(...args),
        patch: jest.fn(),
        delete: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("expo-document-picker", () => ({ getDocumentAsync: jest.fn() }));

import CampaignDraftsSection from "../../../../src/components/admin/billCreator/CampaignDraftsSection";
import PositionsTab from "../../../../src/screens/admin/billCreator/tabs/PositionsTab";

const draft = {
    content_hash: "grp1",
    sender_count: 3,
    letter_count: 2,
    added_words_characters: 0,
    senders_added_words_left_out: 0,
    domain: "everyactioncustom.com",
    rejected: false,
    marked_individual: false,
};

const approvedCampaign = {
    id: 7,
    name: "Complete Streets Letter",
    support: "AGAINST",
    summary: "Opposes the bill.",
    sender_count: 3,
    letter_count: 2,
    source_campaign_draft_hash: "grp1",
    organization_link_decision: null,
    organization_id: null,
    organization_name: null,
};

const tabData = (overrides: Record<string, unknown> = {}, drafts: unknown[] = [draft]) => ({
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
    testimony_campaign_drafts: drafts,
    campaigns: [],
    testimony_claimed_affiliations: [],
    ...overrides,
});

const renderSection = (data: Record<string, unknown>) => {
    const refresh = jest.fn(async () => {});
    render(<CampaignDraftsSection billId={42} data={data} refresh={refresh} />);
    return { refresh };
};

const card = "admin-campaign-draft-grp1";

const writeSummary = (text: string) => {
    fireEvent.press(screen.getByTestId(`${card}-edit`));
    fireEvent.changeText(screen.getByTestId(`${card}-edit-summary`), text);
};

const letters = [
    {
        content_hash: "grp1",
        letters: [
            {
                position: 4,
                text: "First letter body.",
                sender_address: "alice@example.com",
                sender_domain: "example.com",
                repeat: false,
            },
            { position: 9, text: "Second letter body.", sender_address: null, sender_domain: null, repeat: true },
        ],
    },
];

// @lat: [[mobile-bill-creator#Sections#The campaign drafts section]]
describe("CampaignDraftsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({ notice: "Done on 25-0001." });
        mockApiGet.mockResolvedValue({ testimony_campaign_letters: letters });
    });

    it("renders nothing when the bill has no campaign drafts", () => {
        renderSection(tabData({}, []));

        expect(screen.queryByTestId("admin-campaign-drafts")).toBeNull();
    });

    it("shows the unnamed line, the stamps, the evidence and the note", () => {
        renderSection(tabData());

        expect(screen.getByTestId(`${card}-name`)).toHaveTextContent("3 people sent this letter");
        expect(screen.getByText("CAMPAIGN")).toBeTruthy();
        expect(screen.queryByText("APPROVED")).toBeNull();
        expect(screen.getByTestId(`${card}-evidence`)).toHaveTextContent(
            "3 senders · 2 letters · sent through everyactioncustom.com",
        );
        expect(
            screen.getByText("Approving records a campaign position. It never creates an organization."),
        ).toBeTruthy();
        expect(screen.getByTestId(`${card}-stance`)).toHaveTextContent("Support");
        expect(screen.getByTestId(`${card}-summary`)).toHaveTextContent("No summary yet — press Edit to add one.");
        expect(screen.getByTestId(`${card}-approve`)).toHaveTextContent("Approve as this campaign");
    });

    it("clamps a long name until the operator shows the full name", () => {
        const name = "n".repeat(121);
        renderSection(tabData({ campaigns: [{ ...approvedCampaign, name }] }));

        expect(screen.getByTestId(`${card}-name`).props.numberOfLines).toBe(1);
        fireEvent.press(screen.getByText("Show full name"));
        expect(screen.getByTestId(`${card}-name`).props.numberOfLines).toBeUndefined();
        fireEvent.press(screen.getByText("Show less"));
        expect(screen.getByTestId(`${card}-name`).props.numberOfLines).toBe(1);
    });

    it("keeps Approve off until a summary is written", () => {
        renderSection(tabData());

        expect(screen.getByTestId(`${card}-approve`)).toBeDisabled();
        writeSummary("   ");
        expect(screen.getByTestId(`${card}-approve`)).toBeDisabled();
        fireEvent.changeText(screen.getByTestId(`${card}-edit-summary`), "Backs the bill.");
        expect(screen.getByTestId(`${card}-approve`)).toBeEnabled();
    });

    it.each([
        ["the bill has no testimony", { bill: { ...tabData().bill, bill_llm_provisioning: { has_testimony: false } } }],
        [
            "a summary run is in flight",
            {
                bill: {
                    ...tabData().bill,
                    bill_llm_provisioning: { generation_status: "generating", has_testimony: true },
                },
            },
        ],
        [
            "a clean-testimony run covers the bill",
            { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 42 } },
        ],
        ["left-out testimony is unacknowledged", { testimony_coverage: { coverage_gap: true, acknowledged: false } }],
    ])("keeps Approve off while %s", (_reason, overrides) => {
        renderSection(tabData(overrides));
        writeSummary("Backs the bill.");

        expect(screen.getByTestId(`${card}-approve`)).toBeDisabled();
        expect(screen.getByTestId(`${card}-reject`)).toBeEnabled();
    });

    it("approves with the name, position, summary and content hash, then reloads and shows the notice", async () => {
        const { refresh } = renderSection(tabData());
        writeSummary("Backs the bill.");
        fireEvent.changeText(screen.getByTestId(`${card}-edit-name`), "Streets Letter");
        fireEvent.press(screen.getByTestId(`${card}-edit-stance-oppose`));

        fireEvent.press(screen.getByTestId(`${card}-approve`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/campaigns", {
                name: "Streets Letter",
                support: "oppose",
                summary: "Backs the bill.",
                content_hash: "grp1",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(screen.getByTestId(`${card}-notice`)).toHaveTextContent("Done on 25-0001.");
    });

    it("seeds an approved campaign's values and offers Update in place of Mark as Individual Letters", () => {
        renderSection(tabData({ campaigns: [approvedCampaign] }));

        expect(screen.getByTestId(`${card}-name`)).toHaveTextContent("Complete Streets Letter");
        expect(screen.getByText("APPROVED")).toBeTruthy();
        expect(screen.getByTestId(`${card}-stance`)).toHaveTextContent("Oppose");
        expect(screen.getByTestId(`${card}-summary`)).toHaveTextContent("Opposes the bill.");
        expect(screen.getByTestId(`${card}-approve`)).toHaveTextContent("Update this campaign");
        expect(screen.queryByTestId(`${card}-mark-individual`)).toBeNull();
    });

    it("takes the server's new values when a reload changes them and the editor is closed", () => {
        const refresh = jest.fn(async () => {});
        const { rerender } = render(
            <CampaignDraftsSection billId={42} data={tabData({ campaigns: [approvedCampaign] })} refresh={refresh} />,
        );

        rerender(
            <CampaignDraftsSection
                billId={42}
                data={tabData({ campaigns: [{ ...approvedCampaign, summary: "Changed elsewhere." }] })}
                refresh={refresh}
            />,
        );

        expect(screen.getByTestId(`${card}-summary`)).toHaveTextContent("Changed elsewhere.");
    });

    it("keeps typed values when a reload changes the server's while the editor is open", () => {
        const refresh = jest.fn(async () => {});
        const { rerender } = render(
            <CampaignDraftsSection billId={42} data={tabData({ campaigns: [approvedCampaign] })} refresh={refresh} />,
        );
        writeSummary("Typed here.");

        rerender(
            <CampaignDraftsSection
                billId={42}
                data={tabData({ campaigns: [{ ...approvedCampaign, summary: "Changed elsewhere." }] })}
                refresh={refresh}
            />,
        );

        expect(screen.getByTestId(`${card}-edit-summary`).props.value).toBe("Typed here.");
    });

    it.each([
        ["reject", "/bills/42/campaigns/reject_draft"],
        ["mark-individual", "/bills/42/campaigns/mark_individual_draft"],
    ])("%s posts the content hash to its endpoint, then reloads", async (button, path) => {
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId(`${card}-${button}`));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith(path, { content_hash: "grp1" }));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("shows a rejected draft as a stamped row that restores", async () => {
        const { refresh } = renderSection(tabData({}, [{ ...draft, rejected: true }]));

        expect(screen.getByText("REJECTED")).toBeTruthy();
        expect(screen.getByTestId(`${card}-name`)).toHaveTextContent("3 people sent this letter");
        expect(screen.queryByTestId(`${card}-approve`)).toBeNull();

        fireEvent.press(screen.getByTestId(`${card}-restore`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/campaigns/restore_draft", { content_hash: "grp1" }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("shows a draft marked individual as a stamped row with its evidence that restores", async () => {
        renderSection(tabData({}, [{ ...draft, marked_individual: true }]));

        expect(screen.getByText("INDIVIDUAL LETTERS")).toBeTruthy();
        expect(screen.getByTestId(`${card}-name`)).toHaveTextContent(
            "3 people sent this letter · 3 senders · 2 letters · sent through everyactioncustom.com",
        );

        fireEvent.press(screen.getByTestId(`${card}-restore`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/campaigns/restore_draft", { content_hash: "grp1" }),
        );
    });

    it("shows the full card for a draft marked individual that has an approved campaign", () => {
        renderSection(tabData({ campaigns: [approvedCampaign] }, [{ ...draft, marked_individual: true }]));

        expect(screen.queryByText("INDIVIDUAL LETTERS")).toBeNull();
        expect(screen.getByTestId(`${card}-approve`)).toBeTruthy();
    });

    it("shows a refusal's reason from campaign_position", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { campaign_position: "A summary is required" },
                422,
            ),
        );
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId(`${card}-reject`));

        await waitFor(() => expect(screen.getByTestId(`${card}-error`)).toHaveTextContent("A summary is required"));
        expect(refresh).not.toHaveBeenCalled();
    });

    describe("the letters", () => {
        it("offers no letters for a draft with no letters", () => {
            renderSection(tabData({}, [{ ...draft, letter_count: 0 }]));

            expect(screen.queryByTestId(`${card}-letters-toggle`)).toBeNull();
        });

        it("asks for the letters on first open and pages one letter at a time", async () => {
            renderSection(tabData());

            expect(screen.getByTestId(`${card}-letters-toggle`)).toHaveTextContent("Show 2 letters");
            fireEvent.press(screen.getByTestId(`${card}-letters-toggle`));

            expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/positions?testimony_campaign_letters=1");
            await waitFor(() => expect(screen.getByTestId(`${card}-letter`)).toBeTruthy());
            expect(screen.getByText("Letter #4")).toBeTruthy();
            expect(screen.getByText("alice@example.com")).toBeTruthy();
            expect(screen.getByText("First letter body.")).toBeTruthy();
            expect(screen.queryByText("DUPLICATE")).toBeNull();
            expect(screen.getByTestId(`${card}-letter-page`)).toHaveTextContent("1 of 2");

            fireEvent.press(screen.getByTestId(`${card}-letter-next`));

            expect(screen.getByText("Letter #9")).toBeTruthy();
            expect(screen.getByText("Unknown sender")).toBeTruthy();
            expect(screen.getByText("DUPLICATE")).toBeTruthy();
            expect(screen.getByTestId(`${card}-letter-next`)).toBeDisabled();

            fireEvent.press(screen.getByTestId(`${card}-letters-toggle`));
            expect(screen.queryByTestId(`${card}-letter`)).toBeNull();
            fireEvent.press(screen.getByTestId(`${card}-letters-toggle`));
            expect(mockApiGet).toHaveBeenCalledTimes(1);
        });

        it("fills every card from one request", async () => {
            const second = { ...draft, content_hash: "grp2" };
            mockApiGet.mockResolvedValue({
                testimony_campaign_letters: [
                    ...letters,
                    {
                        content_hash: "grp2",
                        letters: [
                            {
                                position: 1,
                                text: "Other body.",
                                sender_address: null,
                                sender_domain: "x.org",
                                repeat: false,
                            },
                        ],
                    },
                ],
            });
            renderSection(tabData({}, [draft, second]));

            fireEvent.press(screen.getByTestId(`${card}-letters-toggle`));
            await waitFor(() => expect(screen.getByTestId(`${card}-letter`)).toBeTruthy());
            fireEvent.press(screen.getByTestId("admin-campaign-draft-grp2-letters-toggle"));

            expect(screen.getByText("Other body.")).toBeTruthy();
            expect(screen.getByText("x.org")).toBeTruthy();
            expect(mockApiGet).toHaveBeenCalledTimes(1);
        });

        it("says when no letter text could be produced", async () => {
            mockApiGet.mockResolvedValue({ testimony_campaign_letters: [] });
            renderSection(tabData());

            fireEvent.press(screen.getByTestId(`${card}-letters-toggle`));

            await waitFor(() =>
                expect(screen.getByTestId(`${card}-letters-empty`)).toHaveTextContent(
                    "No letter text could be produced for this campaign.",
                ),
            );
        });

        it("says the letters could not be loaded and tries again", async () => {
            mockApiGet.mockRejectedValueOnce(new Error("boom"));
            renderSection(tabData());

            fireEvent.press(screen.getByTestId(`${card}-letters-toggle`));
            expect(screen.getByTestId(`${card}-letters-loading`)).toHaveTextContent("Loading letters…");

            await waitFor(() => expect(screen.getByTestId(`${card}-letters-error`)).toBeTruthy());
            expect(screen.getByText("The letters could not be loaded.")).toBeTruthy();
            fireEvent.press(screen.getByTestId(`${card}-letters-retry`));

            await waitFor(() => expect(screen.getByText("First letter body.")).toBeTruthy());
            expect(mockApiGet).toHaveBeenCalledTimes(2);
        });
    });

    it("renders on the Positions tab", () => {
        render(<PositionsTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-campaign-drafts")).toBeTruthy();
    });
});
