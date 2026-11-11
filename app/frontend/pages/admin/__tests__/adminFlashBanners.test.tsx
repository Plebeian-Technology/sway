// The admin Categories and LlmSettings pages must NOT render flash messages
// inline. registerFlashToasts already shows every flash message once,
// through the global Toaster that drops duplicates, so an inline banner said
// the same thing twice.

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

// usePage carries a flash notice — pre-fix both pages rendered it inline.
vi.mock("@inertiajs/react", () => ({
    router: {
        on: vi.fn<() => void>(),
        get: vi.fn<() => void>(),
        post: vi.fn<() => void>(),
        delete: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
    },
    Link: ({ href, children, ...props }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
    // This page polls itself to stay fresh; the poll is a no-op in this test.
    usePoll: function usePoll() {},
    usePage: () => ({ props: { flash: { notice: "Saved OK" } } }),
    useForm: (initial: unknown) => ({
        data: initial,
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        patch: vi.fn<(url?: string, options?: unknown) => void>(),
        processing: false,
        errors: {},
    }),
}));

vi.mock("app/frontend/components/admin/categories/AddCategoryForm", () => ({
    __esModule: true,
    default: () => <div data-testid="add-category-form" />,
}));

vi.mock("app/frontend/components/ui/combobox", () => ({
    Combobox: () => <div data-testid="mock-combobox" />,
}));

// LlmSettings renders a Radix Select — shim it thin.
vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    SelectTrigger: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    SelectItem: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import Categories from "app/frontend/pages/admin/Categories";
import LlmSettings from "app/frontend/pages/admin/LlmSettings";

afterEach(() => cleanup());

describe("Admin pages — no inline flash banner", () => {
    it("Categories does not render the flash notice inline", () => {
        render(<Categories categories={[]} />);
        expect(screen.queryByText("Saved OK")).toBeNull();
    });

    it("LlmSettings does not render the flash notice inline", () => {
        render(
            <LlmSettings
                supported_models={[{ id: "m1", label: "Model 1", selectable: true }]}
                current_summarization_model="m1"
                current_classification_model="m1"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-01-01T00:00:00Z"
            />,
        );
        expect(screen.queryByText("Saved OK")).toBeNull();
    });
});
