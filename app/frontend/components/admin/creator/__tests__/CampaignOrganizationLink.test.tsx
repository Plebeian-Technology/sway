import { act, render, screen, fireEvent } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach } from "vitest";
import CampaignOrganizationLink from "app/frontend/components/admin/creator/campaign-position-card/CampaignOrganizationLink";
import {
    IApprovedCampaign,
    ICampaignOrganizationCandidate,
} from "app/frontend/components/admin/creator/llm-summary/types";

const routerPost = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
    },
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: vi.fn<(payload: { level: string; title: string }) => void>(),
}));

const campaign = (overrides: Partial<IApprovedCampaign> = {}): IApprovedCampaign => ({
    id: 7,
    name: "Complete Streets Letter",
    support: "FOR",
    summary: "Backs it",
    sender_count: 324,
    letter_count: 324,
    source_campaign_draft_hash: "abc123",
    organization_link_decision: null,
    organization_id: null,
    organization_name: null,
    ...overrides,
});

const candidate = (overrides: Partial<ICampaignOrganizationCandidate> = {}): ICampaignOrganizationCandidate => ({
    organization_id: 9,
    organization_name: "Baltimore Renters United",
    evidence_kind: "signature_block",
    letter_count: 12,
    claimed_name: "Baltimore Renters United",
    ...overrides,
});

const renderLink = (props: Partial<React.ComponentProps<typeof CampaignOrganizationLink>> = {}) =>
    render(
        <CampaignOrganizationLink
            billId={1}
            campaign={campaign()}
            candidates={[candidate()]}
            runInFlight={false}
            {...props}
        />,
    );

describe("CampaignOrganizationLink", () => {
    beforeEach(() => {
        routerPost.mockClear();
    });

    // The four states are the whole point of the separate approval: an operator
    // has to be able to tell "nobody looked" from "somebody looked and could not tell".
    describe("the four states", () => {
        it("reads as not decided when nobody has been asked", () => {
            renderLink();

            expect(screen.getByTestId("campaign-organization-undecided-stamp")).toBeInTheDocument();
        });

        it("names the linked organization", () => {
            renderLink({
                campaign: campaign({
                    organization_link_decision: "linked",
                    organization_id: 9,
                    organization_name: "Baltimore Renters United",
                }),
            });

            expect(screen.getByTestId("campaign-organization-linked-stamp")).toHaveTextContent(
                "Baltimore Renters United",
            );
        });

        it("shows a definitive no-organization decision", () => {
            renderLink({ campaign: campaign({ organization_link_decision: "none" }) });

            expect(screen.getByTestId("campaign-organization-none-stamp")).toBeInTheDocument();
        });

        it("shows an explicitly deferred decision, distinct from never having been asked", () => {
            renderLink({ campaign: campaign({ organization_link_decision: "undetermined" }) });

            expect(screen.getByTestId("campaign-organization-undetermined-stamp")).toBeInTheDocument();
            expect(screen.queryByTestId("campaign-organization-undecided-stamp")).not.toBeInTheDocument();
        });
    });

    describe("recording a decision", () => {
        it("posts a definitive none without an organization", () => {
            renderLink();

            fireEvent.click(screen.getByTestId("btn-campaign-organization-none"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/7/link_organization",
                { decision: "none" },
                expect.objectContaining({ preserveScroll: true }),
            );
        });

        it("posts a deferred decision without an organization", () => {
            renderLink();

            fireEvent.click(screen.getByTestId("btn-campaign-organization-undetermined"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/7/link_organization",
                { decision: "undetermined" },
                expect.objectContaining({ preserveScroll: true }),
            );
        });

        // The server refuses a link with no organization chosen, so an enabled
        // button here would always be a dead click.
        it("cannot link until an organization is chosen", () => {
            renderLink();

            expect(screen.getByTestId("btn-link-campaign-organization")).toBeDisabled();
        });

        it("offers the link once the campaign already carries one", () => {
            renderLink({
                campaign: campaign({
                    organization_link_decision: "linked",
                    organization_id: 9,
                    organization_name: "Baltimore Renters United",
                }),
            });

            expect(screen.getByTestId("btn-link-campaign-organization")).toBeEnabled();
        });

        it("creates and links a new organization when typed into the input with or without existing candidates", () => {
            renderLink();

            const input = screen.getByTestId("input-create-campaign-organization");
            fireEvent.change(input, { target: { value: "  Harford Road Neighbors  " } });

            const linkBtn = screen.getByTestId("btn-link-campaign-organization");
            expect(linkBtn).toBeEnabled();
            expect(linkBtn).toHaveTextContent("Create and link organization");

            fireEvent.click(linkBtn);

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/7/link_organization",
                { decision: "linked", organization_name: "Harford Road Neighbors" },
                expect.objectContaining({ preserveScroll: true }),
            );
        });

        it("creates and links a new organization when candidates is empty", () => {
            renderLink({ candidates: [] });

            const input = screen.getByTestId("input-create-campaign-organization");
            fireEvent.change(input, { target: { value: "Lauraville Improvement Association" } });

            const linkBtn = screen.getByTestId("btn-link-campaign-organization");
            expect(linkBtn).toBeEnabled();
            expect(linkBtn).toHaveTextContent("Create and link organization");

            fireEvent.click(linkBtn);

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/7/link_organization",
                { decision: "linked", organization_name: "Lauraville Improvement Association" },
                expect.objectContaining({ preserveScroll: true }),
            );
        });

        it("syncs choice and button state when campaign.organization_id changes across Inertia redirects", () => {
            const { rerender } = render(
                <CampaignOrganizationLink
                    billId={1}
                    campaign={campaign({
                        organization_link_decision: "linked",
                        organization_id: 42,
                        organization_name: "Newly Created Org",
                    })}
                    candidates={[]}
                    runInFlight={false}
                />,
            );

            expect(screen.getByTestId("btn-link-campaign-organization")).toBeEnabled();
            expect(screen.getByTestId("campaign-organization-no-candidates")).toHaveTextContent(
                "Linked to Newly Created Org. No other organization on this bill matches this campaign's letters.",
            );

            rerender(
                <CampaignOrganizationLink
                    billId={1}
                    campaign={campaign({
                        organization_link_decision: "none",
                        organization_id: null,
                        organization_name: null,
                    })}
                    candidates={[]}
                    runInFlight={false}
                />,
            );

            expect(screen.getByTestId("btn-link-campaign-organization")).toBeDisabled();
        });

        it("resets a selected candidate choice when decision changes to none and restores serverChoice when the new-org input is cleared", () => {
            const { rerender } = render(
                <CampaignOrganizationLink
                    billId={1}
                    campaign={campaign({
                        organization_link_decision: "linked",
                        organization_id: 9,
                        organization_name: "Baltimore Renters United",
                    })}
                    candidates={[candidate()]}
                    runInFlight={false}
                />,
            );

            const input = screen.getByTestId("input-create-campaign-organization");
            fireEvent.change(input, { target: { value: "Temporary Name" } });
            expect(screen.getByTestId("btn-link-campaign-organization")).toHaveTextContent(
                "Create and link organization",
            );

            fireEvent.change(input, { target: { value: "" } });
            expect(screen.getByTestId("btn-link-campaign-organization")).toBeEnabled();
            expect(screen.getByTestId("btn-link-campaign-organization")).toHaveTextContent("Change the organization");

            rerender(
                <CampaignOrganizationLink
                    billId={1}
                    campaign={campaign({
                        organization_link_decision: null,
                        organization_id: null,
                        organization_name: null,
                    })}
                    candidates={[candidate()]}
                    runInFlight={false}
                />,
            );

            fireEvent.click(screen.getByTestId("select-campaign-organization-trigger"));
            fireEvent.click(screen.getByRole("option", { name: /Baltimore Renters United/i }));
            expect(screen.getByTestId("btn-link-campaign-organization")).toBeEnabled();

            rerender(
                <CampaignOrganizationLink
                    billId={1}
                    campaign={campaign({
                        organization_link_decision: "none",
                        organization_id: null,
                        organization_name: null,
                    })}
                    candidates={[candidate()]}
                    runInFlight={false}
                />,
            );

            expect(screen.getByTestId("btn-link-campaign-organization")).toBeDisabled();
        });

        it("restores serverChoice on onSuccess when submitting a newOrganizationName that resolves to the already-linked organization", () => {
            render(
                <CampaignOrganizationLink
                    billId={1}
                    campaign={campaign({
                        organization_link_decision: "linked",
                        organization_id: 9,
                        organization_name: "Baltimore Renters United",
                    })}
                    candidates={[candidate()]}
                    runInFlight={false}
                />,
            );

            const input = screen.getByTestId("input-create-campaign-organization");
            fireEvent.change(input, { target: { value: "baltimore renters united" } });
            fireEvent.click(screen.getByTestId("btn-link-campaign-organization"));

            const opts = routerPost.mock.calls[0][2] as { onSuccess?: () => void; onFinish?: () => void };
            act(() => {
                opts.onSuccess?.();
                opts.onFinish?.();
            });

            expect(input).toHaveValue("");
            expect(screen.getByTestId("btn-link-campaign-organization")).toBeEnabled();
            expect(screen.getByTestId("btn-link-campaign-organization")).toHaveTextContent("Change the organization");
        });
    });

    describe("the evidence an operator is asked to judge", () => {
        it("says how many letters signed off as the organization", () => {
            renderLink();

            expect(screen.getByTestId("select-campaign-organization-trigger")).toBeInTheDocument();
        });

        it("says so plainly when nothing on the bill matches", () => {
            renderLink({ candidates: [] });

            expect(screen.getByTestId("campaign-organization-no-candidates")).toBeInTheDocument();
            expect(screen.queryByTestId("select-campaign-organization-trigger")).not.toBeInTheDocument();
        });

        // Empty candidates is a real answer, not an inability to ask: the two
        // decisions that need no organization must still be recordable.
        it("still lets both no-organization answers be recorded with no candidates", () => {
            renderLink({ candidates: [] });

            expect(screen.getByTestId("btn-campaign-organization-none")).toBeEnabled();
            expect(screen.getByTestId("btn-campaign-organization-undetermined")).toBeEnabled();
        });
    });

    it("records nothing while a clean-testimony run is in flight", () => {
        renderLink({ runInFlight: true });

        expect(screen.getByTestId("btn-campaign-organization-none")).toBeDisabled();
        expect(screen.getByTestId("btn-campaign-organization-undetermined")).toBeDisabled();
    });
});
