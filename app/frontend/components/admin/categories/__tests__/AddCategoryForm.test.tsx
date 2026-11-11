// The server refuses a category name nested or flat ("category.name"). This form used to
// read only the nested shape, showing no message on a refusal. These tests cover both.

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

let mockErrors: Record<string, unknown> = {};

vi.mock("@inertiajs/react", () => ({
    useForm: (initial: unknown) => ({
        data: initial,
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        post: vi.fn<(url?: string, options?: unknown) => void>(),
        reset: vi.fn<() => void>(),
        processing: false,
        errors: mockErrors,
    }),
}));

import AddCategoryForm from "app/frontend/components/admin/categories/AddCategoryForm";

afterEach(() => {
    cleanup();
    mockErrors = {};
});

describe("AddCategoryForm — validation errors survive either errors shape (C1-IN-07)", () => {
    it("renders a nested category.name error", () => {
        mockErrors = { category: { name: "has already been taken" } };
        render(<AddCategoryForm />);

        expect(screen.getByText("has already been taken")).toBeInTheDocument();
    });

    it("renders a dotted-path category.name error", () => {
        mockErrors = { "category.name": "has already been taken" };
        render(<AddCategoryForm />);

        expect(screen.getByText("has already been taken")).toBeInTheDocument();
    });

    it("renders no error text when the create was accepted", () => {
        render(<AddCategoryForm />);

        expect(screen.queryByText("has already been taken")).toBeNull();
    });
});
