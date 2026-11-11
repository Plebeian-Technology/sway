// @lat: [[notifications-tab-url#Why switching a tab reaches no server]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

// Nothing on this page may make a request to change tabs. Any call through the
// router is a failure, so the whole module is a spy that must stay untouched.
const routerVisit = vi.fn<(url: string, options?: Record<string, unknown>) => void>();
vi.mock("@inertiajs/react", () => ({
    router: {
        visit: (url: string, options?: Record<string, unknown>) => routerVisit(url, options),
        get: (url: string, options?: Record<string, unknown>) => routerVisit(url, options),
        reload: (options?: Record<string, unknown>) => routerVisit("reload", options),
    },
}));

const detectSupportMock = vi.fn<() => "supported" | "unsupported">(() => "supported");
vi.mock("app/frontend/hooks/notifications/usePushSubscription", () => ({
    detectSupport: () => detectSupportMock(),
}));

vi.mock("app/frontend/components/notifications/PushNotificationsPanel", () => ({
    __esModule: true,
    default: () => <div data-testid="push-panel" />,
}));
vi.mock("app/frontend/components/notifications/SmsNotificationsPanel", () => ({
    __esModule: true,
    default: () => <div data-testid="sms-panel" />,
}));
// The Organizations tab panel calls useForm, which this file's bare-bones
// @inertiajs/react stand-in deliberately leaves out — so stub it like the others.
vi.mock("app/frontend/components/notifications/OrganizationsNotificationsPanel", () => ({
    __esModule: true,
    default: () => <div data-testid="orgs-panel" />,
}));

// A minimal stand-in for Tabs that exposes the selected value and the buttons.
vi.mock("app/frontend/components/ui/tabs", () => ({
    Tabs: ({ value, onValueChange, children }: any) => (
        <div data-testid="tabs" data-active={value}>
            <button type="button" data-testid="tab-push" onClick={() => onValueChange("push")}>
                Push
            </button>
            <button type="button" data-testid="tab-sms" onClick={() => onValueChange("sms")}>
                SMS
            </button>
            <button type="button" data-testid="tab-organizations" onClick={() => onValueChange("organizations")}>
                Organizations
            </button>
            <button type="button" data-testid="tab-bogus" onClick={() => onValueChange("bogus")}>
                Bogus
            </button>
            {children}
        </div>
    ),
    TabsList: ({ children }: any) => <div>{children}</div>,
    TabsTrigger: ({ children }: any) => <span>{children}</span>,
    TabsContent: ({ children }: any) => <div>{children}</div>,
}));

import Notifications from "app/frontend/pages/Notifications";

const setUrl = (search: string) => window.history.replaceState({}, "", `/notifications${search}`);
const renderPage = () =>
    render(<Notifications user={{} as any} sway_locale={{} as any} subscriptions={[]} sms_phone="" />);
const activeTab = () => screen.getByTestId("tabs").getAttribute("data-active");
const currentSearch = () => window.location.search;

afterEach(() => {
    cleanup();
    routerVisit.mockReset();
    detectSupportMock.mockReturnValue("supported");
});

describe("Notifications — tab derived from URL", () => {
    it("renders the lead copy mentioning Bill of the Month", () => {
        renderPage();
        expect(screen.getByText("Choose how Sway reaches you when a new Bill of the Month is released.")).toBeTruthy();
    });

    it("falls back to the sms tab when push is unsupported and no tab is in the URL", () => {
        detectSupportMock.mockReturnValue("unsupported");
        setUrl("");
        renderPage();
        expect(activeTab()).toBe("sms");
    });

    it("derives the active tab from ?tab= in the URL", () => {
        setUrl("?tab=sms");
        renderPage();
        expect(activeTab()).toBe("sms");
    });

    it("derives the active tab from canonical ?notifications_tab= in the URL", () => {
        setUrl("?notifications_tab=sms");
        renderPage();
        expect(activeTab()).toBe("sms");

        setUrl("?notifications_tab=organizations");
        cleanup();
        renderPage();
        expect(activeTab()).toBe("organizations");

        setUrl("?notifications_tab=push");
        cleanup();
        renderPage();
        expect(activeTab()).toBe("push");
    });

    it("falls back to legacy ?tab= when ?notifications_tab= is absent", () => {
        setUrl("?tab=sms");
        renderPage();
        expect(activeTab()).toBe("sms");

        setUrl("?tab=organizations");
        cleanup();
        renderPage();
        expect(activeTab()).toBe("organizations");
    });

    it("gives precedence to ?notifications_tab= when both ?notifications_tab= and legacy ?tab= are present", () => {
        setUrl("?notifications_tab=organizations&tab=sms");
        renderPage();
        expect(activeTab()).toBe("organizations");

        setUrl("?notifications_tab=push&tab=organizations");
        cleanup();
        renderPage();
        expect(activeTab()).toBe("push");

        setUrl("?notifications_tab=bogus&tab=sms");
        cleanup();
        renderPage();
        expect(activeTab()).toBe("push");
    });

    it("writes the selected tab to the URL without reaching the server", () => {
        setUrl("");
        renderPage();
        fireEvent.click(screen.getByTestId("tab-sms"));
        const params = new URLSearchParams(currentSearch());
        expect(params.get("notifications_tab")).toBe("sms");
        expect(params.get("tab")).toBeNull();
        expect(activeTab()).toBe("sms");
        expect(routerVisit).not.toHaveBeenCalled();
    });

    // The Organizations tab is the one a browser test walks back to on a fresh
    // visit, so it has to survive the round trip in the address. Nothing at this
    // level used to check it: the stand-in above offered only Push and SMS.
    it("derives the Organizations tab from ?tab=organizations", () => {
        setUrl("?tab=organizations");
        renderPage();
        expect(activeTab()).toBe("organizations");
    });

    it("writes the Organizations tab to the URL when it is picked", () => {
        setUrl("");
        renderPage();
        fireEvent.click(screen.getByTestId("tab-organizations"));
        const params = new URLSearchParams(currentSearch());
        expect(params.get("notifications_tab")).toBe("organizations");
        expect(params.get("tab")).toBeNull();
        expect(activeTab()).toBe("organizations");
        expect(routerVisit).not.toHaveBeenCalled();
    });

    it("sets notifications_tab and deletes legacy tab for each channel without router navigation", () => {
        setUrl("?tab=sms");
        renderPage();
        fireEvent.click(screen.getByTestId("tab-push"));
        let params = new URLSearchParams(currentSearch());
        expect(params.get("notifications_tab")).toBe("push");
        expect(params.get("tab")).toBeNull();
        expect(activeTab()).toBe("push");
        expect(routerVisit).not.toHaveBeenCalled();

        fireEvent.click(screen.getByTestId("tab-sms"));
        params = new URLSearchParams(currentSearch());
        expect(params.get("notifications_tab")).toBe("sms");
        expect(params.get("tab")).toBeNull();
        expect(activeTab()).toBe("sms");
        expect(routerVisit).not.toHaveBeenCalled();

        fireEvent.click(screen.getByTestId("tab-organizations"));
        params = new URLSearchParams(currentSearch());
        expect(params.get("notifications_tab")).toBe("organizations");
        expect(params.get("tab")).toBeNull();
        expect(activeTab()).toBe("organizations");
        expect(routerVisit).not.toHaveBeenCalled();
    });

    // @lat: [[notifications-tab-url#The Notifications tab in the URL#Why switching a tab reaches no server]]
    it("survives the two onValueChange calls Radix makes for one click", () => {
        setUrl("");
        renderPage();

        fireEvent.click(screen.getByTestId("tab-sms"));
        fireEvent.click(screen.getByTestId("tab-sms"));

        const params = new URLSearchParams(currentSearch());
        expect(params.get("notifications_tab")).toBe("sms");
        expect(params.get("tab")).toBeNull();
        expect(activeTab()).toBe("sms");
        expect(routerVisit).not.toHaveBeenCalled();
    });

    // The address carries the tab, so it has to survive being read back after a
    // click rather than only living in React state.
    it("keeps the picked tab on a rerender that re-reads the URL", () => {
        setUrl("");
        const { rerender } = renderPage();

        fireEvent.click(screen.getByTestId("tab-organizations"));
        rerender(<Notifications user={{} as any} sway_locale={{} as any} subscriptions={[]} sms_phone="" />);

        expect(activeTab()).toBe("organizations");
    });

    // A tab name the page does not have must not reach the address, and must not
    // leave the page showing nothing. Both directions are checked, because the
    // guard that rejects the name is one line and is easy to drop.
    it("ignores a tab name the page does not have, in the URL and on a click", () => {
        setUrl("?tab=bogus");
        renderPage();
        expect(activeTab()).toBe("push");

        // The address already says bogus, so what this checks is that the click
        // leaves it exactly as it found it rather than writing it again.
        const before = currentSearch();
        fireEvent.click(screen.getByTestId("tab-bogus"));
        expect(currentSearch()).toBe(before);
        expect(routerVisit).not.toHaveBeenCalled();
    });

    it("reflects a URL change on rerender WITHOUT a popstate event (pure derive)", () => {
        setUrl("?tab=push");
        const { rerender } = renderPage();
        expect(activeTab()).toBe("push");

        // A server redirect can still change the tab in the address; the page has
        // to follow it without a back/forward event.
        setUrl("?tab=sms");
        rerender(<Notifications user={{} as any} sway_locale={{} as any} subscriptions={[]} sms_phone="" />);
        expect(activeTab()).toBe("sms");
    });
});
