// @lat: [[parity-copy-snapshot-testing#Why parityCopy.test.ts checks the nested shape]]

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

// ---------------------------------------------------------------------------
// The oldest names — now reached through nested paths
// ---------------------------------------------------------------------------
describe("PARITY_COPY — keys (nested paths)", () => {
    it("bills.title is defined", () => {
        expect(PARITY_COPY.bills.title).toBeDefined();
        expect(typeof PARITY_COPY.bills.title).toBe("string");
    });

    it("bills.showingCount is a function", () => {
        expect(typeof PARITY_COPY.bills.showingCount).toBe("function");
        expect(PARITY_COPY.bills.showingCount(5, "Baltimore")).toBe("Showing 5 bills for Baltimore.");
    });

    it("bills.noneFound is a function", () => {
        expect(typeof PARITY_COPY.bills.noneFound).toBe("function");
        expect(PARITY_COPY.bills.noneFound("Baltimore")).toBe("No bills found for Baltimore.");
    });

    it("bills.loading is defined", () => {
        expect(PARITY_COPY.bills.loading).toBeDefined();
    });

    it("org.noSupport is defined", () => {
        expect(PARITY_COPY.org.noSupport).toBeDefined();
    });

    it("votePanel.title is defined", () => {
        expect(PARITY_COPY.votePanel.title).toBeDefined();
    });

    it("notifications.lead mentions Bill of the Month", () => {
        expect(PARITY_COPY.notifications.lead).toBe(
            "Choose how Sway reaches you. Bill of the Month is on by default; the others are opt-in.",
        );
    });

    it("notifications.botmAnnouncement has monthly label and description", () => {
        expect(PARITY_COPY.notifications.botmAnnouncement.label).toBe("Bill of the Month announcements");
        expect(PARITY_COPY.notifications.botmAnnouncement.description).toBe(
            "We'll let you know when a new Bill of the Month is published.",
        );
    });

    it("bill.showMore and bill.showLess are defined", () => {
        expect(PARITY_COPY.bill.showMore).toBeDefined();
        expect(PARITY_COPY.bill.showLess).toBeDefined();
    });

    it("bill.shareBill is 'Share bill'", () => {
        expect(PARITY_COPY.bill.shareBill).toBe("Share bill");
    });

    it("bill.shareCopied is 'Bill link copied to clipboard.'", () => {
        expect(PARITY_COPY.bill.shareCopied).toBe("Bill link copied to clipboard.");
    });

    it("bill.voteComparisonPlaceholder has no copy that counts the users still needed", () => {
        expect(PARITY_COPY.bill.voteComparisonPlaceholder).not.toHaveProperty("votersNeeded");
    });

    it("bill.voteComparisonPlaceholder carries the invite, sign-up and no-number strings", () => {
        const copy = PARITY_COPY.bill.voteComparisonPlaceholder;
        expect(copy.invitePrompt).toBe("Invite others by sharing Sway");
        expect(copy.copyInviteLink).toBe("Copy invite link");
        expect(copy.inviteLinkCopied).toBe("Invite link copied to clipboard.");
        expect(copy.signUp).toBe("Sign up");
        expect(copy.notEnoughVotes).toBe("Not enough votes yet");
    });
});

// ---------------------------------------------------------------------------
// A later group of names — also reached through nested paths
// ---------------------------------------------------------------------------
describe("PARITY_COPY — Legislators keys (nested)", () => {
    it("legislators.title is 'Legislators'", () => {
        expect(PARITY_COPY.legislators.title).toBe("Legislators");
    });

    it("legislators.searchAgain is 'Search again'", () => {
        expect(PARITY_COPY.legislators.searchAgain).toBe("Search again");
    });

    it("legislators.noneFound is a function producing the correct string", () => {
        expect(typeof PARITY_COPY.legislators.noneFound).toBe("function");
        expect(PARITY_COPY.legislators.noneFound("Baltimore")).toBe("No representatives found for Baltimore.");
    });

    // The words shown when every known term has finished, which is
    // not the same as never having found anybody.
    it("legislators.waitingForNewTerm names the place and says the term ended", () => {
        expect(typeof PARITY_COPY.legislators.waitingForNewTerm).toBe("function");
        expect(PARITY_COPY.legislators.waitingForNewTerm("Baltimore")).toBe(
            "The term has ended for Baltimore. Sway does not have the new term's representatives yet.",
        );
    });

    it("legislators.showCharts is 'Show voter agreement'", () => {
        expect(PARITY_COPY.legislators.showCharts).toBe("Show voter agreement");
    });

    it("legislators.hideCharts is 'Hide voter agreement'", () => {
        expect(PARITY_COPY.legislators.hideCharts).toBe("Hide voter agreement");
    });

    it("legislators.loading is defined", () => {
        expect(PARITY_COPY.legislators.loading).toBeDefined();
    });

    it("legislators.scoreAgreed is 'Agreed'", () => {
        expect(PARITY_COPY.legislators.scoreAgreed).toBe("Agreed");
    });

    it("legislators.scoreDisagreed is 'Disagreed'", () => {
        expect(PARITY_COPY.legislators.scoreDisagreed).toBe("Disagreed");
    });

    it("legislators.scoreNoVote is 'No vote'", () => {
        expect(PARITY_COPY.legislators.scoreNoVote).toBe("No vote");
    });
});

describe("PARITY_COPY — Organizations keys (nested)", () => {
    it("orgs.title is 'Organizations'", () => {
        expect(PARITY_COPY.orgs.title).toBe("Organizations");
    });

    it("orgs.noneFound is a function", () => {
        expect(typeof PARITY_COPY.orgs.noneFound).toBe("function");
        expect(PARITY_COPY.orgs.noneFound("Baltimore")).toBe("No organizations found for Baltimore.");
    });

    it("orgs.noPositions is the public organization page's positions empty state", () => {
        expect(PARITY_COPY.orgs.noPositions).toBe("Sway has not recorded any positions from this organization yet.");
    });

    it("orgs.noBillPositions says Sway found no organization positions on the bill", () => {
        expect(PARITY_COPY.orgs.noBillPositions).toBe("Sway has not found any organization positions on this bill.");
    });

    it("orgs.subtitle says Sway recorded the positions", () => {
        expect(PARITY_COPY.orgs.subtitle).toBe(
            "Browse organizations and the positions Sway has recorded from public testimony and news.",
        );
    });

    it("feed.organizationPositionRecordedPrefix names Sway as the recorder", () => {
        expect(PARITY_COPY.feed.organizationPositionRecordedPrefix).toBe("Sway recorded that");
    });

    it("notifications.orgPositionTaken says Sway records the position", () => {
        expect(PARITY_COPY.notifications.orgPositionTaken.label).toBe(
            "Sway recorded a position from an organization you track",
        );
        expect(PARITY_COPY.notifications.orgPositionTaken.description).toBe(
            "When Sway records a position from an organization you track on a new bill.",
        );
    });

    it("orgNotifications.panelDescription says Sway records the positions", () => {
        expect(PARITY_COPY.orgNotifications.panelDescription).toBe(
            "Get notified when Sway records or updates a position from an organization you track.",
        );
    });

    it("orgs.listNotice says where positions come from and when an organization is affiliated", () => {
        expect(PARITY_COPY.orgs.listNotice).toBe(
            "Sway compiles organizations' positions from public testimony and news reporting. An organization is not affiliated with Sway unless its page says it manages its positions on Sway.",
        );
    });

    it("orgs.notAffiliated names the organization and says Sway compiled its positions", () => {
        expect(PARITY_COPY.orgs.notAffiliated("Bikemore")).toBe(
            "Bikemore is not affiliated with Sway and is not responsible for its content. Sway compiled these positions from public testimony and news reporting.",
        );
    });

    it("orgs.managedOnSway names the organization", () => {
        expect(PARITY_COPY.orgs.managedOnSway("Bikemore")).toBe("Bikemore manages its positions on Sway.");
    });

    it("orgs.postedBy and orgs.compiledBySway are the per-position tags", () => {
        expect(PARITY_COPY.orgs.postedBy("Bikemore")).toBe("Posted by Bikemore");
        expect(PARITY_COPY.orgs.compiledBySway).toBe("Compiled by Sway");
    });
});

describe("PARITY_COPY — Memberships keys (nested)", () => {
    it("memberships.title is 'My Organizations'", () => {
        expect(PARITY_COPY.memberships.title).toBe("My Organizations");
    });

    it("memberships.activeSectionLabel is 'Active'", () => {
        expect(PARITY_COPY.memberships.activeSectionLabel).toBe("Active");
    });

    it("memberships.pendingSectionLabel is 'Pending invites'", () => {
        expect(PARITY_COPY.memberships.pendingSectionLabel).toBe("Pending invites");
    });

    it("memberships.tabPositions is 'Positions'", () => {
        expect(PARITY_COPY.memberships.tabPositions).toBe("Positions");
    });

    it("memberships.tabPendingChanges is 'Pending Changes'", () => {
        expect(PARITY_COPY.memberships.tabPendingChanges).toBe("Pending Changes");
    });

    it("memberships.tabMembers is 'Members'", () => {
        expect(PARITY_COPY.memberships.tabMembers).toBe("Members");
    });
});

describe("PARITY_COPY — Positions + Pending Changes keys (nested)", () => {
    it("positions.supports is 'Supports'", () => {
        expect(PARITY_COPY.positions.supports).toBe("Supports");
    });

    it("positions.opposes is 'Opposes'", () => {
        expect(PARITY_COPY.positions.opposes).toBe("Opposes");
    });

    it("pendingChanges.approveLabel is 'Approve change'", () => {
        expect(PARITY_COPY.pendingChanges.approveLabel).toBe("Approve change");
    });

    it("pendingChanges.rejectLabel is 'Reject'", () => {
        expect(PARITY_COPY.pendingChanges.rejectLabel).toBe("Reject");
    });

    it("pendingChanges.rejectConfirmTitle is 'Reject this proposed change?'", () => {
        expect(PARITY_COPY.pendingChanges.rejectConfirmTitle).toBe("Reject this proposed change?");
    });
});

describe("PARITY_COPY — Members + Invite keys (nested)", () => {
    it("members.leaveOrgLabel is 'Leave organization'", () => {
        expect(PARITY_COPY.members.leaveOrgLabel).toBe("Leave organization");
    });

    it("members.inviteLabel is 'Invite a member'", () => {
        expect(PARITY_COPY.members.inviteLabel).toBe("Invite a member");
    });

    it("members.inviteSubmitLabel is 'Send invite'", () => {
        expect(PARITY_COPY.members.inviteSubmitLabel).toBe("Send invite");
    });

    it("members.inviteSuccess is 'Invitation sent.'", () => {
        expect(PARITY_COPY.members.inviteSuccess).toBe("Invitation sent.");
    });

    it("memberships.acceptLabel is 'Accept invite'", () => {
        expect(PARITY_COPY.memberships.acceptLabel).toBe("Accept invite");
    });

    it("memberships.declineLabel is 'Decline'", () => {
        expect(PARITY_COPY.memberships.declineLabel).toBe("Decline");
    });

    it("positions.newModalTitle is 'Propose new position'", () => {
        expect(PARITY_COPY.positions.newModalTitle).toBe("Propose new position");
    });

    it("positions.newSubmitLabel is 'Propose position'", () => {
        expect(PARITY_COPY.positions.newSubmitLabel).toBe("Propose position");
    });
});

// ---------------------------------------------------------------------------
// The newest names
// ---------------------------------------------------------------------------
describe("PARITY_COPY — auth.passkeyPanel keys", () => {
    it("auth.passkeyPanel.title is 'Start or login with your phone number.'", () => {
        expect(PARITY_COPY.auth.passkeyPanel.title).toBe("Start or login with your phone number.");
    });

    it("auth.passkeyPanel.continuePhone is 'Continue with Phone'", () => {
        expect(PARITY_COPY.auth.passkeyPanel.continuePhone).toBe("Continue with Phone");
    });

    it("auth.passkeyPanel.confirmCode is 'Confirm code'", () => {
        expect(PARITY_COPY.auth.passkeyPanel.confirmCode).toBe("Confirm code");
    });

    it("auth.passkeyPanel.resendCode is 'Send a new code'", () => {
        expect(PARITY_COPY.auth.passkeyPanel.resendCode).toBe("Send a new code");
    });

    it("auth.passkeyPanel.codeResent is 'We sent you a new code.'", () => {
        expect(PARITY_COPY.auth.passkeyPanel.codeResent).toBe("We sent you a new code.");
    });

    it("auth.passkeyPanel.passkeyUnsupported says the browser can't use passkeys and names no protocol", () => {
        expect(PARITY_COPY.auth.passkeyPanel.passkeyUnsupported).toBe(
            "This browser can't use passkeys yet. Update your browser or try another one.",
        );
    });

    // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
    it("auth.passkeyPanel.passkeyFallback names no cause and points at the phone form", () => {
        expect(PARITY_COPY.auth.passkeyPanel.passkeyFallback).toBe(
            "Signing in with a passkey didn't work. Use your phone number below to continue.",
        );
    });
});

describe("PARITY_COPY — auth.hero keys", () => {
    it("auth.hero.headline is 'Remember in November.'", () => {
        expect(PARITY_COPY.auth.hero.headline).toBe("Remember in November.");
    });

    it("auth.hero.paragraph is a non-empty string", () => {
        expect(typeof PARITY_COPY.auth.hero.paragraph).toBe("string");
        expect(PARITY_COPY.auth.hero.paragraph.length).toBeGreaterThan(0);
    });
});

describe("PARITY_COPY — address keys", () => {
    it("address.complete.heading is 'Complete your registration'", () => {
        expect(PARITY_COPY.address.complete.heading).toBe("Complete your registration");
    });

    it("address.complete.cta is 'Find My Representatives'", () => {
        expect(PARITY_COPY.address.complete.cta).toBe("Find My Representatives");
    });

    it("address.helper.registerToVoteUrl matches canonical value", () => {
        expect(PARITY_COPY.address.helper.registerToVoteUrl).toBe("https://www.vote.org/register-to-vote/");
    });

    it("address.switchConfirm defines editLead, title, body, confirmCta, and cancelCta for audited address switches", () => {
        expect(PARITY_COPY.address.switchConfirm).toEqual({
            editLead:
                "Updating your address re-checks your district and legislators. Switching to a new address deactivates your current representative links, updates district scores, and records the change for audit.",
            title: "Confirm address change",
            body: "Switching your address will deactivate your current representative links, match you with the representatives for your new address, and record this switch so accounts cannot vote across multiple districts or locales.",
            confirmCta: "Confirm address change",
            cancelCta: "Keep current address",
        });
    });
});

describe("PARITY_COPY — publicTestimony keys (nested)", () => {
    it("publicTestimony.modal has expected values", () => {
        expect(PARITY_COPY.publicTestimony.modal.title).toBe("Public Testimony");
        expect(PARITY_COPY.publicTestimony.modal.subtitle(1)).toBe("1 constituent letter");
        expect(PARITY_COPY.publicTestimony.modal.subtitle(5)).toBe("5 constituent letters");
        expect(PARITY_COPY.publicTestimony.modal.allTab).toBe("All");
        expect(PARITY_COPY.publicTestimony.modal.supportTab).toBe("Support");
        expect(PARITY_COPY.publicTestimony.modal.opposeTab).toBe("Oppose");
        expect(PARITY_COPY.publicTestimony.modal.neutralTab).toBe("Neutral");
    });

    it("publicTestimony.section has expected values", () => {
        expect(PARITY_COPY.publicTestimony.section.heading).toBe("Public Testimony");
        expect(PARITY_COPY.publicTestimony.section.subtitle(1)).toBe("1 constituent letter submitted");
        expect(PARITY_COPY.publicTestimony.section.subtitle(12)).toBe("12 constituent letters submitted");
        expect(PARITY_COPY.publicTestimony.section.browseButton).toBe("Browse Public Letters");
        expect(PARITY_COPY.publicTestimony.section.supportPill).toBe("Support");
        expect(PARITY_COPY.publicTestimony.section.opposePill).toBe("Oppose");
        expect(PARITY_COPY.publicTestimony.section.neutralPill).toBe("Neutral");
    });
});

// ---------------------------------------------------------------------------
// Guard: the old flat names such as billsTitle must not come back
// ---------------------------------------------------------------------------
describe("PARITY_COPY — no flat-camelCase root keys after migration", () => {
    it("billsTitle is undefined (migrated to bills.title)", () => {
        expect((PARITY_COPY as Record<string, unknown>).billsTitle).toBeUndefined();
    });

    it("legislatorsTitle is undefined (migrated to legislators.title)", () => {
        expect((PARITY_COPY as Record<string, unknown>).legislatorsTitle).toBeUndefined();
    });

    it("orgsTitle is undefined (migrated to orgs.title)", () => {
        expect((PARITY_COPY as Record<string, unknown>).orgsTitle).toBeUndefined();
    });

    it("membershipsTitle is undefined (migrated to memberships.title)", () => {
        expect((PARITY_COPY as Record<string, unknown>).membershipsTitle).toBeUndefined();
    });

    it("votePanelTitle is undefined (migrated to votePanel.title)", () => {
        expect((PARITY_COPY as Record<string, unknown>).votePanelTitle).toBeUndefined();
    });
});

// @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
const REPO_ROOT = resolve(__dirname, "../../..");
const PARITY_COPY_FILE = resolve(REPO_ROOT, "app/frontend/sway_constants/parityCopy.ts");
const SELF_TEST_FILE = resolve(__dirname, "parityCopy.test.ts");
const FRONTEND_DIR = resolve(REPO_ROOT, "app/frontend");
const MOBILE_DIR = resolve(REPO_ROOT, "mobile");

const filesUnder = (dir: string, skipDirs: readonly string[] = []): string[] =>
    readdirSync(dir).flatMap((entry) => {
        if (skipDirs.includes(entry)) return [];
        const path = join(dir, entry);
        if (statSync(path).isDirectory()) return filesUnder(path, skipDirs);
        return path.endsWith(".ts") || path.endsWith(".tsx") ? [path] : [];
    });

const leafPaths = (value: unknown, prefix: string): string[] => {
    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
        return Object.entries(value as Record<string, unknown>).flatMap(([key, child]) =>
            leafPaths(child, prefix ? `${prefix}.${key}` : key),
        );
    }
    return [prefix];
};

describe("PARITY_COPY orphans — every leaf key has a reader", () => {
    const leaves = leafPaths(PARITY_COPY, "");

    it("has a non-empty leaf vocabulary to check against", () => {
        expect(leaves.length).toBeGreaterThan(100);
    });

    const haystacks = [
        ...filesUnder(FRONTEND_DIR),
        ...filesUnder(MOBILE_DIR, ["node_modules", "android", "ios", ".expo", ".maestro"]),
    ]
        .filter((path) => path !== PARITY_COPY_FILE && path !== SELF_TEST_FILE)
        .map((path) => readFileSync(path, "utf8"));

    it("every leaf key is read by PARITY_COPY.<path> somewhere outside its own definition and shape test", () => {
        const orphans = leaves.filter((path) => {
            const re = new RegExp(`PARITY_COPY\\.${path.replace(/\./g, "\\.")}\\b`);
            return !haystacks.some((text) => re.test(text));
        });

        expect(orphans).toEqual([]);
    });
});
