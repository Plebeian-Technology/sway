import { PARITY_COPY } from "../../app/frontend/sway_constants/parityCopy";

// @lat: [[parity-copy-snapshot-testing#Mobile nested-key shape guard]]
const COPY = PARITY_COPY as unknown as {
    auth: {
        passkeyPanel: Record<string, string>;
        deviceUnsupported: Record<string, string>;
    };
    address: {
        complete: Record<string, string>;
        helper: Record<string, string>;
    };
    bills: Record<string, unknown>;
    legislators: Record<string, unknown>;
    orgs: Record<string, unknown>;
    memberships: Record<string, unknown>;
    votePanel: Record<string, unknown>;
    billOfTheMonth: Record<string, unknown>;
    vote: Record<string, unknown>;
    localePicker: Record<string, unknown>;
    positions: Record<string, unknown>;
    members: Record<string, unknown>;
    pendingChanges: Record<string, unknown>;
    bill: { content: Record<string, unknown>; shareBill: string; shareCopied: string };
    notifications: {
        title: string;
        lead: string;
        botmAnnouncement: { label: string; description: string };
    };
};

describe("parityCopy nested-key contract", () => {
    it("nested auth.passkeyPanel keys exist with correct strings", () => {
        expect(COPY.auth.passkeyPanel.title).toBe("Start or login with your phone number.");
        expect(typeof COPY.auth.passkeyPanel.subtitle).toBe("string");
        expect(COPY.auth.passkeyPanel.continuePhone).toBe("Continue with Phone");
        expect(COPY.auth.passkeyPanel.confirmCode).toBe("Confirm code");
        expect(COPY.auth.passkeyPanel.cancelCta).toBe("Cancel");
        expect(COPY.auth.passkeyPanel.previewSway).toBe("Preview Sway");
        expect(COPY.auth.passkeyPanel.workingOn).toBe("Working on it");
    });

    it("nested auth.deviceUnsupported keys exist with correct strings", () => {
        expect(COPY.auth.deviceUnsupported.title).toBe("This device can't use Sway");
        expect(COPY.auth.deviceUnsupported.cta).toBe("Back to sign in");
        expect(typeof COPY.auth.deviceUnsupported.body1).toBe("string");
        expect(COPY.auth.deviceUnsupported.body1.length).toBeGreaterThan(0);
        expect(typeof COPY.auth.deviceUnsupported.body2).toBe("string");
        expect(COPY.auth.deviceUnsupported.body2.length).toBeGreaterThan(0);
    });

    it("nested address.complete keys exist with correct strings", () => {
        expect(COPY.address.complete.heading).toBe("Complete your registration");
        expect(COPY.address.complete.cta).toBe("Find My Representatives");
        expect(COPY.address.complete.cancelCta).toBe("Log Out");
        expect(typeof COPY.address.complete.lead).toBe("string");
        expect(COPY.address.complete.lead.length).toBeGreaterThan(0);
    });

    it("nested address.helper.* URLs match web canonical values", () => {
        expect(COPY.address.helper.registerToVoteUrl).toBe("https://www.vote.org/register-to-vote/");
        expect(COPY.address.helper.checkRegistrationUrl).toBe("https://www.vote.org/am-i-registered-to-vote/");
        expect(COPY.address.helper.viewOnGitHubUrl).toBe("https://github.com/Plebeian-Technology/sway");
    });

    it("Phase 34/35 keys migrated to nested paths and are non-empty strings", () => {
        expect(typeof COPY.bills.title).toBe("string");
        expect((COPY.bills.title as string).length).toBeGreaterThan(0);
        expect(COPY.bills.allBillsTitle).toBe("All Bills");
        expect(COPY.bills.pastBillsOfTheMonthTitle).toBe("Past Bills of the Month");
        expect(COPY.bills.sessionLabel).toBe("Session");

        // @lat: [[bills-controller-design#Why the search and sort labels in parityCopy.ts note the underlying split]]
        expect(typeof COPY.bills.searchPlaceholder).toBe("string");
        expect(typeof COPY.bills.searchLabel).toBe("string");
        expect(typeof COPY.bills.sortLabel).toBe("string");
        const sortOptions = COPY.bills.sortOptions as { value: string; label: string }[];
        expect(sortOptions.length).toBeGreaterThan(0);
        sortOptions.forEach((option) => {
            expect(option.value).toMatch(/^[a-z_]+:(asc|desc)$/);
            expect(option.label.length).toBeGreaterThan(0);
        });

        expect(typeof COPY.legislators.title).toBe("string");
        expect((COPY.legislators.title as string).length).toBeGreaterThan(0);

        expect(typeof COPY.orgs.title).toBe("string");
        expect((COPY.orgs.title as string).length).toBeGreaterThan(0);

        expect(typeof COPY.memberships.title).toBe("string");
        expect((COPY.memberships.title as string).length).toBeGreaterThan(0);

        expect(typeof COPY.votePanel.title).toBe("string");
        expect((COPY.votePanel.title as string).length).toBeGreaterThan(0);

        expect(typeof COPY.billOfTheMonth.empty).toBe("string");
        expect((COPY.billOfTheMonth.empty as string).length).toBeGreaterThan(0);
        expect(COPY.billOfTheMonth.title).toBe("Bill of the Month");
        expect(COPY.billOfTheMonth.empty).toBe("No Bill of the Month is featured right now. Check back soon.");

        expect(typeof COPY.vote.confirmTitle).toBe("string");
        expect((COPY.vote.confirmTitle as string).length).toBeGreaterThan(0);

        expect(typeof COPY.localePicker.title).toBe("string");
        expect((COPY.localePicker.title as string).length).toBeGreaterThan(0);

        expect(typeof COPY.positions.empty).toBe("string");
        expect((COPY.positions.empty as string).length).toBeGreaterThan(0);

        expect(typeof COPY.members.empty).toBe("string");
        expect((COPY.members.empty as string).length).toBeGreaterThan(0);

        expect(typeof COPY.pendingChanges.empty).toBe("string");
        expect((COPY.pendingChanges.empty as string).length).toBeGreaterThan(0);

        expect(typeof COPY.bill.content.howOthersVoted).toBe("string");
        expect((COPY.bill.content.howOthersVoted as string).length).toBeGreaterThan(0);

        expect(typeof COPY.bill.shareBill).toBe("string");
        expect(COPY.bill.shareBill).toBe("Share bill");

        expect(typeof COPY.notifications.title).toBe("string");
        expect(typeof COPY.notifications.lead).toBe("string");
        expect(COPY.notifications.botmAnnouncement.label).toBe("Bill of the Month announcements");
        expect(COPY.notifications.botmAnnouncement.description).toBe(
            "We'll let you know when a new Bill of the Month is released.",
        );
    });

    it("no flat-camelCase root keys survive after migration", () => {
        // Treat it as a plain record so we can look up keys that must not exist.
        const root = PARITY_COPY as Record<string, unknown>;

        expect(root.billsTitle).toBeUndefined();
        expect(root.legislatorsTitle).toBeUndefined();
        expect(root.orgsTitle).toBeUndefined();
        expect(root.membershipsTitle).toBeUndefined();
        expect(root.votePanelTitle).toBeUndefined();
    });
});
