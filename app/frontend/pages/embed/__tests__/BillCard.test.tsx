import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import BillCard, { IEmbedBill } from "app/frontend/pages/embed/BillCard";

const mockBill: IEmbedBill = {
    id: 42,
    identifier: "SB 123",
    title: "Clean Water and Community Health Act",
    brief_summary: "An act to protect municipal watersheds and improve tap water quality across the state.",
    sway_locale: {
        name: "baltimore-maryland-united_states",
        jurisdiction: "Maryland",
        state: "maryland",
    },
    current_status: "In Committee",
    pro_count: 75,
    con_count: 25,
    total_votes: 100,
    comparison_suppressed: false,
    voters_needed: 0,
    cta_url: "/bills/42?partner=the-banner&ref=art-99",
};

describe("embed/BillCard", () => {
    afterEach(() => {
        cleanup();
    });

    it("renders the bill identifier and jurisdiction badges", () => {
        render(<BillCard bill={mockBill} />);

        expect(screen.getByTestId("bill-identifier").textContent).toBe("SB 123");
        expect(screen.getByTestId("locale-badge").textContent).toBe("Maryland");
        expect(screen.getByTestId("bill-status").textContent).toBe("In Committee");
    });

    it("renders the bill title and brief summary", () => {
        render(<BillCard bill={mockBill} />);

        expect(screen.getByTestId("bill-title").textContent).toBe("Clean Water and Community Health Act");
        expect(screen.getByTestId("bill-summary").textContent).toContain("protect municipal watersheds");
    });

    it("renders the vote breakdown meter with support and oppose percentages when votes exist", () => {
        render(<BillCard bill={mockBill} />);

        expect(screen.getByTestId("vote-meter")).toBeTruthy();
        expect(screen.getByText(/Support 75 \(75%\)/)).toBeTruthy();
        expect(screen.getByText(/Oppose 25 \(25%\)/)).toBeTruthy();
        expect(screen.getByTestId("pro-bar")).toBeTruthy();
        expect(screen.getByTestId("con-bar")).toBeTruthy();
    });

    // @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it("shows the placeholder with a sign-up link and no percentage below the ten-voter minimum", () => {
        const nineVotesBill: IEmbedBill = {
            ...mockBill,
            pro_count: null,
            con_count: null,
            total_votes: 9,
            comparison_suppressed: true,
            voters_needed: 1,
        };

        render(<BillCard bill={nineVotesBill} />);

        expect(screen.queryByTestId("vote-meter")).toBeNull();
        const placeholder = screen.getByTestId("vote-meter-suppressed");
        expect(placeholder.textContent).toContain("Visual comparisons will be shown when 1 more user has voted.");
        expect(placeholder.textContent).not.toContain("%");
        const signUp = screen.getByRole("link", { name: "Sign up" });
        expect(signUp.getAttribute("href")).toBe("/?partner=the-banner&ref=art-99");
        expect(signUp.getAttribute("target")).toBe("_blank");
        expect(signUp.getAttribute("rel")).toBe("noopener noreferrer");
    });

    it("sends a plain sign-in link when the embed carries no partner", () => {
        render(<BillCard bill={{ ...mockBill, comparison_suppressed: true, voters_needed: 1, cta_url: "" }} />);

        expect(screen.getByRole("link", { name: "Sign up" }).getAttribute("href")).toBe("/");
    });

    it("keeps counts hidden when a payload says suppressed but still carries them", () => {
        render(<BillCard bill={{ ...mockBill, comparison_suppressed: true, voters_needed: 3 }} />);

        expect(screen.queryByTestId("vote-meter")).toBeNull();
        expect(screen.getByTestId("vote-meter-suppressed").textContent).not.toMatch(/75|25|%/);
    });

    it("treats top-level props with no flag as suppressed", () => {
        render(<BillCard id={mockBill.id} title={mockBill.title} pro_count={75} con_count={25} total_votes={100} />);

        expect(screen.queryByTestId("vote-meter")).toBeNull();
        expect(screen.getByTestId("vote-meter-suppressed").textContent).toContain("Not enough votes yet");
    });

    it("renders the CTA button linking to cta_url with target=_blank and rel=noopener noreferrer", () => {
        render(<BillCard bill={mockBill} />);

        const ctaButton = screen.getByTestId("act-cta-button");
        expect(ctaButton.getAttribute("href")).toBe("/bills/42?partner=the-banner&ref=art-99");
        expect(ctaButton.getAttribute("target")).toBe("_blank");
        expect(ctaButton.getAttribute("rel")).toBe("noopener noreferrer");
        expect(ctaButton.textContent).toContain("Act on this bill");
    });

    it("accepts top-level props directly without nested bill object", () => {
        render(<BillCard {...mockBill} />);

        expect(screen.getByTestId("bill-identifier").textContent).toBe("SB 123");
        expect(screen.getByTestId("bill-title").textContent).toBe("Clean Water and Community Health Act");
        const ctaButton = screen.getByTestId("act-cta-button");
        expect(ctaButton.getAttribute("href")).toBe("/bills/42?partner=the-banner&ref=art-99");
    });

    it("rejects non-http/https cta_url protocols and falls back to /bills/:id", () => {
        render(<BillCard bill={{ ...mockBill, cta_url: "javascript:alert(1)" }} />);

        const ctaButton = screen.getByTestId("act-cta-button");
        expect(ctaButton.getAttribute("href")).toBe("/bills/42");
    });
});

describe("embed/BillCard iframe resize & lifecycle", () => {
    let originalParent: typeof window.parent;
    let mockPostMessage: ReturnType<typeof vi.fn<(message: unknown, targetOrigin: string) => void>>;
    let observeMock: ReturnType<typeof vi.fn<(target: Element) => void>>;
    let disconnectMock: ReturnType<typeof vi.fn<() => void>>;
    let observerCallback: ResizeObserverCallback | null = null;

    beforeEach(() => {
        mockPostMessage = vi.fn<(message: unknown, targetOrigin: string) => void>();
        originalParent = window.parent;
        observeMock = vi.fn<(target: Element) => void>();
        disconnectMock = vi.fn<() => void>();
        observerCallback = null;

        Object.defineProperty(window, "parent", {
            value: { postMessage: mockPostMessage },
            writable: true,
            configurable: true,
        });

        class MockResizeObserver {
            constructor(callback: ResizeObserverCallback) {
                observerCallback = callback;
            }
            observe = observeMock;
            unobserve = vi.fn<(target: Element) => void>();
            disconnect = disconnectMock;
        }
        vi.stubGlobal("ResizeObserver", MockResizeObserver);

        Object.defineProperty(document.documentElement, "scrollHeight", {
            value: 300,
            configurable: true,
            writable: true,
        });
    });

    afterEach(() => {
        cleanup();
        Object.defineProperty(window, "parent", {
            value: originalParent,
            writable: true,
            configurable: true,
        });
        vi.unstubAllGlobals();
        vi.restoreAllMocks();
    });

    it("posts sway:resize on initial mount when embedded in an iframe", () => {
        render(<BillCard bill={mockBill} />);

        expect(mockPostMessage).toHaveBeenCalledWith(
            expect.objectContaining({
                type: "sway:resize",
                billId: 42,
                height: expect.any(Number),
            }),
            "*",
        );
    });

    it("instantiates ResizeObserver and observes document.body", () => {
        render(<BillCard bill={mockBill} />);

        expect(observeMock).toHaveBeenCalledWith(document.body);
    });

    it("dispatches sway:resize postMessage when ResizeObserver triggers reflow", () => {
        render(<BillCard bill={mockBill} />);
        mockPostMessage.mockClear();

        Object.defineProperty(document.documentElement, "scrollHeight", {
            value: 345,
            configurable: true,
        });

        act(() => {
            observerCallback?.([] as ResizeObserverEntry[], {} as ResizeObserver);
        });

        expect(mockPostMessage).toHaveBeenCalledWith(
            {
                type: "sway:resize",
                billId: 42,
                height: 345,
            },
            "*",
        );
    });

    it("disconnects ResizeObserver and removes resize event listener on unmount", () => {
        const removeEventListenerSpy = vi.spyOn(window, "removeEventListener");
        const { unmount } = render(<BillCard bill={mockBill} />);

        expect(disconnectMock).not.toHaveBeenCalled();

        unmount();

        expect(disconnectMock).toHaveBeenCalledTimes(1);
        expect(removeEventListenerSpy).toHaveBeenCalledWith("resize", expect.any(Function));
    });

    it("renders title with tooltip and line-clamping class", () => {
        render(<BillCard bill={mockBill} />);

        const titleEl = screen.getByTestId("bill-title");
        expect(titleEl.getAttribute("title")).toBe("Clean Water and Community Health Act");
        expect(titleEl.className).toContain("line-clamp-2");
        expect(titleEl.className).toContain("sm:line-clamp-3");
    });
});
