// CollapsiblePanel remembers whether it was left open or closed, in the
// browser's localStorage.

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Replace the shadcn Accordion with plain HTML, so the tests can open and close
// it without relying on Radix's portal handling, which jsdom cannot run.
vi.mock("app/frontend/components/ui/accordion", () => {
    let currentValue = "";
    let currentOnValueChange: ((v: string) => void) | undefined;
    return {
        Accordion: ({
            value,
            onValueChange,
            children,
            type: _type,
            collapsible: _collapsible,
            ...rest
        }: {
            value: string;
            onValueChange?: (v: string) => void;
            children: React.ReactNode;
            type?: string;
            collapsible?: boolean;
            [k: string]: unknown;
        }) => {
            currentValue = value;
            currentOnValueChange = onValueChange;
            return (
                <div data-state={value === "open" ? "open" : "closed"} {...rest}>
                    {children}
                </div>
            );
        },
        AccordionItem: ({ children, ...rest }: { children: React.ReactNode; [k: string]: unknown }) => (
            <div {...rest}>{children}</div>
        ),
        AccordionTrigger: ({ children, ...rest }: { children: React.ReactNode; [k: string]: unknown }) => (
            <button
                type="button"
                onClick={() => {
                    const next = currentValue === "open" ? "" : "open";
                    currentOnValueChange?.(next);
                }}
                {...rest}
            >
                {children}
            </button>
        ),
        AccordionContent: ({ children, ...rest }: { children: React.ReactNode; [k: string]: unknown }) => (
            <div {...rest}>{children}</div>
        ),
    };
});

import CollapsiblePanel from "app/frontend/components/CollapsiblePanel";

const KEY = "sway:test:accordion:demo";

describe("CollapsiblePanel", () => {
    beforeEach(() => {
        window.localStorage.clear();
    });
    afterEach(() => cleanup());

    it("defaults to open when no localStorage value is set", () => {
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo">
                <div data-testid="child">child content</div>
            </CollapsiblePanel>,
        );
        const root = screen.getByTestId(`collapsible-panel-${KEY}`);
        expect(root.getAttribute("data-state")).toBe("open");
        expect(screen.getByTestId("child")).toBeDefined();
    });

    it("reads stored '0' as closed", () => {
        window.localStorage.setItem(KEY, "0");
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo">
                <div data-testid="child">child content</div>
            </CollapsiblePanel>,
        );
        const root = screen.getByTestId(`collapsible-panel-${KEY}`);
        expect(root.getAttribute("data-state")).toBe("closed");
    });

    it("reads stored '1' as open", () => {
        window.localStorage.setItem(KEY, "1");
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo">
                <div data-testid="child">child content</div>
            </CollapsiblePanel>,
        );
        const root = screen.getByTestId(`collapsible-panel-${KEY}`);
        expect(root.getAttribute("data-state")).toBe("open");
    });

    it("toggling writes '0' to localStorage when collapsing from default-open", () => {
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo">
                <div>child</div>
            </CollapsiblePanel>,
        );
        fireEvent.click(screen.getByTestId(`collapsible-panel-trigger-${KEY}`));
        expect(window.localStorage.getItem(KEY)).toBe("0");
        expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("closed");
    });

    it("toggling writes '1' to localStorage when expanding from stored-closed", () => {
        window.localStorage.setItem(KEY, "0");
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo">
                <div>child</div>
            </CollapsiblePanel>,
        );
        fireEvent.click(screen.getByTestId(`collapsible-panel-trigger-${KEY}`));
        expect(window.localStorage.getItem(KEY)).toBe("1");
        expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("open");
    });

    it("uses different storage keys for independent instances", () => {
        const KEY_A = "sway:test:accordion:a";
        const KEY_B = "sway:test:accordion:b";
        window.localStorage.setItem(KEY_A, "0");
        window.localStorage.setItem(KEY_B, "1");
        render(
            <>
                <CollapsiblePanel storageKey={KEY_A} title="A">
                    <div>a</div>
                </CollapsiblePanel>
                <CollapsiblePanel storageKey={KEY_B} title="B">
                    <div>b</div>
                </CollapsiblePanel>
            </>,
        );
        expect(screen.getByTestId(`collapsible-panel-${KEY_A}`).getAttribute("data-state")).toBe("closed");
        expect(screen.getByTestId(`collapsible-panel-${KEY_B}`).getAttribute("data-state")).toBe("open");
    });

    it("honors defaultOpen=false when no localStorage value is set", () => {
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo" defaultOpen={false}>
                <div>child</div>
            </CollapsiblePanel>,
        );
        expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("closed");
    });

    it("ignores defaultOpen when localStorage value is present", () => {
        window.localStorage.setItem(KEY, "1");
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo" defaultOpen={false}>
                <div>child</div>
            </CollapsiblePanel>,
        );
        expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("open");
    });

    // @lat: [[collapsible-panel#Storage that is not there falls back to the default]]
    it("renders on its default rather than throwing when the browser refuses storage", () => {
        const original = Object.getOwnPropertyDescriptor(window, "localStorage");
        Object.defineProperty(window, "localStorage", {
            configurable: true,
            get() {
                throw new DOMException("The operation is insecure.", "SecurityError");
            },
        });

        try {
            render(
                <CollapsiblePanel storageKey={KEY} title="Demo" defaultOpen={false}>
                    <div>child</div>
                </CollapsiblePanel>,
            );
            expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("closed");

            fireEvent.click(screen.getByTestId(`collapsible-panel-trigger-${KEY}`));

            expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("open");
        } finally {
            if (original) Object.defineProperty(window, "localStorage", original);
        }
    });

    // @lat: [[collapsible-panel#Storage that is not there falls back to the default]]
    it("falls back to defaultOpen when the stored value is one it never wrote", () => {
        window.localStorage.setItem(KEY, "true");
        render(
            <CollapsiblePanel storageKey={KEY} title="Demo">
                <div>child</div>
            </CollapsiblePanel>,
        );
        expect(screen.getByTestId(`collapsible-panel-${KEY}`).getAttribute("data-state")).toBe("open");
    });
});
