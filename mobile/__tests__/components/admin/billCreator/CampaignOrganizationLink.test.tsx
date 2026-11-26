import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        get: jest.fn(),
        patch: jest.fn(),
        delete: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import CampaignOrganizationLink from "../../../../src/components/admin/billCreator/CampaignOrganizationLink";

type Props = React.ComponentProps<typeof CampaignOrganizationLink>;

const campaign = (overrides: Partial<Props["campaign"]> = {}): Props["campaign"] => ({
    id: 7,
    organization_link_decision: null,
    organization_id: null,
    organization_name: null,
    ...overrides,
});

const candidate = (overrides: Partial<Props["candidates"][number]> = {}): Props["candidates"][number] => ({
    organization_id: 9,
    organization_name: "Baltimore Renters United",
    evidence_kind: "signature_block",
    letter_count: 12,
    claimed_name: "Baltimore Renters United",
    ...overrides,
});

const linkedCampaign = () =>
    campaign({
        organization_link_decision: "linked",
        organization_id: 9,
        organization_name: "Baltimore Renters United",
    });

const root = "admin-campaign-organization-7";
const linkPath = "/bills/42/campaigns/7/link_organization";

const renderLink = (props: Partial<Props> = {}) => {
    const refresh = jest.fn(async () => {});
    const view = render(
        <CampaignOrganizationLink
            billId={42}
            campaign={campaign()}
            candidates={[candidate()]}
            runInFlight={false}
            refresh={refresh}
            {...props}
        />,
    );
    return { refresh, ...view };
};

const linkButton = () => screen.getByTestId(`${root}-link`);

// @lat: [[mobile-bill-creator#Sections#The campaign drafts section#Linking a campaign to an organization]]
describe("CampaignOrganizationLink", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({ notice: "Recorded on 25-0001." });
    });

    describe("the four states", () => {
        it("reads as not decided when nobody has been asked", () => {
            renderLink();

            expect(screen.getByTestId(`${root}-stamp`)).toHaveTextContent("NOT DECIDED");
        });

        it("names the linked organization", () => {
            renderLink({ campaign: linkedCampaign() });

            expect(screen.getByTestId(`${root}-stamp`)).toHaveTextContent("Baltimore Renters United");
        });

        it("falls back to LINKED when the linked organization has no name", () => {
            renderLink({ campaign: campaign({ organization_link_decision: "linked", organization_id: 9 }) });

            expect(screen.getByTestId(`${root}-stamp`)).toHaveTextContent("LINKED");
        });

        it("shows a definitive no-organization decision", () => {
            renderLink({ campaign: campaign({ organization_link_decision: "none" }) });

            expect(screen.getByTestId(`${root}-stamp`)).toHaveTextContent("NO ORGANIZATION");
        });

        it("shows a deferred decision apart from never having been asked", () => {
            renderLink({ campaign: campaign({ organization_link_decision: "undetermined" }) });

            expect(screen.getByTestId(`${root}-stamp`)).toHaveTextContent("NOT DETERMINABLE YET");
        });
    });

    describe("recording a decision", () => {
        it("posts the chosen organization", async () => {
            const { refresh } = renderLink();

            fireEvent.press(screen.getByTestId(`${root}-option-9`));
            fireEvent.press(linkButton());

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith(linkPath, { decision: "linked", organization_id: "9" }),
            );
            await waitFor(() => expect(refresh).toHaveBeenCalled());
            expect(screen.getByTestId(`${root}-notice`)).toHaveTextContent("Recorded on 25-0001.");
        });

        it("cannot link until an organization is chosen", () => {
            renderLink();

            expect(linkButton()).toBeDisabled();
            expect(linkButton()).toHaveTextContent("Link this organization");
        });

        it("offers the change once the campaign already carries a link", () => {
            renderLink({ campaign: linkedCampaign() });

            expect(linkButton()).toBeEnabled();
            expect(linkButton()).toHaveTextContent("Change the organization");
        });

        it("posts a definitive none without an organization", async () => {
            renderLink();

            fireEvent.press(screen.getByTestId(`${root}-none`));

            await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith(linkPath, { decision: "none" }));
        });

        it("posts a deferred decision without an organization", async () => {
            renderLink();

            fireEvent.press(screen.getByTestId(`${root}-undetermined`));

            await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith(linkPath, { decision: "undetermined" }));
        });

        it("creates and links a typed organization, trimmed, in place of the chosen one", async () => {
            renderLink();

            fireEvent.press(screen.getByTestId(`${root}-option-9`));
            fireEvent.changeText(screen.getByTestId(`${root}-new-name`), "  Harford Road Neighbors  ");

            expect(linkButton()).toBeEnabled();
            expect(linkButton()).toHaveTextContent("Create and link organization");
            fireEvent.press(linkButton());

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith(linkPath, {
                    decision: "linked",
                    organization_name: "Harford Road Neighbors",
                }),
            );
        });

        it("creates an organization from the return key", async () => {
            renderLink({ candidates: [] });

            const field = screen.getByTestId(`${root}-new-name`);
            fireEvent.changeText(field, "Lauraville Improvement Association");
            fireEvent(field, "submitEditing");

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith(linkPath, {
                    decision: "linked",
                    organization_name: "Lauraville Improvement Association",
                }),
            );
        });

        it("ignores the return key on a blank name", () => {
            renderLink();

            const field = screen.getByTestId(`${root}-new-name`);
            fireEvent.changeText(field, "   ");
            fireEvent(field, "submitEditing");

            expect(mockApiPost).not.toHaveBeenCalled();
        });

        it("restores the server's choice when the typed name is cleared", () => {
            renderLink({ campaign: linkedCampaign() });

            const field = screen.getByTestId(`${root}-new-name`);
            fireEvent.changeText(field, "Temporary Name");
            expect(linkButton()).toHaveTextContent("Create and link organization");

            fireEvent.changeText(field, "");
            expect(linkButton()).toBeEnabled();
            expect(linkButton()).toHaveTextContent("Change the organization");
        });

        it("clears a typed name when an option is chosen", () => {
            renderLink();

            fireEvent.changeText(screen.getByTestId(`${root}-new-name`), "Temporary Name");
            fireEvent.press(screen.getByTestId(`${root}-option-9`));

            expect(screen.getByTestId(`${root}-new-name`).props.value).toBe("");
            expect(linkButton()).toHaveTextContent("Link this organization");
        });

        it("empties the typed name and keeps the choice after a link succeeds", async () => {
            renderLink({ campaign: linkedCampaign() });

            const field = screen.getByTestId(`${root}-new-name`);
            fireEvent.changeText(field, "baltimore renters united");
            fireEvent.press(linkButton());

            await waitFor(() => expect(screen.getByTestId(`${root}-notice`)).toBeTruthy());
            expect(screen.getByTestId(`${root}-new-name`).props.value).toBe("");
            expect(linkButton()).toBeEnabled();
            expect(linkButton()).toHaveTextContent("Change the organization");
        });

        it("clears the chosen organization after a none answer succeeds", async () => {
            renderLink();

            fireEvent.press(screen.getByTestId(`${root}-option-9`));
            expect(linkButton()).toBeEnabled();
            fireEvent.press(screen.getByTestId(`${root}-none`));

            await waitFor(() => expect(screen.getByTestId(`${root}-notice`)).toBeTruthy());
            expect(linkButton()).toBeDisabled();
        });

        it("takes the server's choice again when the campaign's link changes", () => {
            const { rerender } = renderLink({ campaign: linkedCampaign(), candidates: [] });
            expect(linkButton()).toBeEnabled();

            rerender(
                <CampaignOrganizationLink
                    billId={42}
                    campaign={campaign({ organization_link_decision: "none" })}
                    candidates={[]}
                    runInFlight={false}
                    refresh={jest.fn(async () => {})}
                />,
            );

            expect(linkButton()).toBeDisabled();
        });
    });

    describe("the evidence an operator is asked to judge", () => {
        it("says how many letters signed off as the claimed name", () => {
            renderLink();

            expect(screen.getByTestId(`${root}-option-9`)).toHaveTextContent(
                'Baltimore Renters United — 12 letters signed off as "Baltimore Renters United"',
            );
        });

        it("says a single letter named the organization when it has no claimed name", () => {
            renderLink({ candidates: [candidate({ letter_count: 1, claimed_name: null })] });

            expect(screen.getByTestId(`${root}-option-9`)).toHaveTextContent(
                "Baltimore Renters United — 1 letter named this organization",
            );
        });

        it("says when the organization already holds a position", () => {
            renderLink({ candidates: [candidate({ evidence_kind: "bill_position", claimed_name: null })] });

            expect(screen.getByTestId(`${root}-option-9`)).toHaveTextContent(
                "Baltimore Renters United — Already holds a position on this bill",
            );
        });

        it("offers the linked organization when the candidates lack it", () => {
            renderLink({
                campaign: campaign({
                    organization_link_decision: "linked",
                    organization_id: 42,
                    organization_name: "Newly Created Org",
                }),
            });

            expect(screen.getByTestId(`${root}-option-42`)).toHaveTextContent(
                "Newly Created Org — Linked to this campaign",
            );
        });

        it("says so plainly when nothing on the bill matches", () => {
            renderLink({ candidates: [] });

            expect(screen.getByTestId(`${root}-no-candidates`)).toHaveTextContent(
                "No organization on this bill matches this campaign's letters. Record one of the answers below.",
            );
            expect(screen.queryByTestId(`${root}-option-9`)).toBeNull();
        });

        it("names the link when nothing else matches", () => {
            renderLink({ campaign: linkedCampaign(), candidates: [] });

            expect(screen.getByTestId(`${root}-no-candidates`)).toHaveTextContent(
                "Linked to Baltimore Renters United. No other organization on this bill matches this campaign's letters.",
            );
        });

        it("still records both no-organization answers with no candidates", () => {
            renderLink({ candidates: [] });

            expect(screen.getByTestId(`${root}-none`)).toBeEnabled();
            expect(screen.getByTestId(`${root}-undetermined`)).toBeEnabled();
        });
    });

    it("records nothing while a run is in flight", () => {
        renderLink({ campaign: linkedCampaign(), runInFlight: true });

        expect(screen.getByTestId(`${root}-none`)).toBeDisabled();
        expect(screen.getByTestId(`${root}-undetermined`)).toBeDisabled();
        expect(linkButton()).toBeDisabled();
        expect(screen.getByTestId(`${root}-new-name`).props.editable).toBe(false);
    });

    it("shows a refusal's reason from campaign_organization and does not reload", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { campaign_organization: "That organization belongs to a different locale than this bill" },
                422,
            ),
        );
        const { refresh } = renderLink();

        fireEvent.press(screen.getByTestId(`${root}-none`));

        await waitFor(() =>
            expect(screen.getByTestId(`${root}-error`)).toHaveTextContent(
                "That organization belongs to a different locale than this bill",
            ),
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows the server's message when the refusal names no reason", async () => {
        mockApiPost.mockRejectedValue(new ApiRequestError("server_error", "Something broke.", undefined, 500));
        renderLink();

        fireEvent.press(screen.getByTestId(`${root}-none`));

        await waitFor(() => expect(screen.getByTestId(`${root}-error`)).toHaveTextContent("Something broke."));
    });
});
