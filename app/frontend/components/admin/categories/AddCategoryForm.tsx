// @lat: [[admin-categories-frontend-row-and-form#Why AddCategoryForm.tsx uses useForm and CategoryRow.tsx uses router.patch]]
// @lat: [[inertia-nested-form-errors-accessor#Reading errors from a nested Inertia form]]

import { useForm } from "@inertiajs/react";
import { useRef } from "react";

import { scrollToCategoryRow } from "app/frontend/components/admin/categories/categoryRowDom";
import { type ICategory } from "app/frontend/components/admin/categories/CategoryRow";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";

type CategoryFormErrors = {
    category?: {
        name?: string;
    };
};

const categoryNameError = (errors: unknown): string | undefined => {
    const flat = (errors as Record<string, string | undefined>)["category.name"];
    const nested = (errors as CategoryFormErrors).category?.name;
    return flat ?? nested;
};

type FormShape = {
    category: {
        name: string;
    };
};

const AddCategoryForm: React.FC = () => {
    const form = useForm<FormShape>({ category: { name: "" } });
    const inputRef = useRef<HTMLInputElement>(null);

    const nameError = categoryNameError(form.errors);

    const handleSubmit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        // @lat: [[admin-categories-frontend-row-and-form#Refocusing the add-category input after submit]]
        const submittedName = form.data.category.name.trim();
        form.post("/admin/categories", {
            preserveScroll: true,
            onSuccess: (page) => {
                form.reset();
                window.setTimeout(() => inputRef.current?.focus(), 0);
                const categories = (page.props.categories ?? []) as ICategory[];
                const created = categories.find((c) => c.name === submittedName);
                if (created) scrollToCategoryRow(created.id);
            },
        });
    };

    return (
        <form onSubmit={handleSubmit}>
            <div className="flex flex-col gap-2">
                <div className="flex gap-2">
                    <label htmlFor="new-category-name" className="sr-only">
                        New category name
                    </label>
                    <Input
                        ref={inputRef}
                        id="new-category-name"
                        placeholder="New category name"
                        value={form.data.category.name}
                        onChange={(e) => form.setData("category.name", e.target.value)}
                        aria-describedby={nameError ? "new-category-name-error" : undefined}
                        aria-invalid={nameError ? "true" : undefined}
                        // @lat: [[admin-categories-frontend-row-and-form#Why AddCategoryForm.tsx uses useForm and CategoryRow.tsx uses router.patch]]
                        disabled={form.processing}
                        className="flex-1"
                    />
                    <Button type="submit" variant="default" disabled={form.processing}>
                        {form.processing ? "Adding..." : "Add category"}
                    </Button>
                </div>
                {nameError ? (
                    <p id="new-category-name-error" role="alert" className="text-sm text-destructive">
                        {nameError}
                    </p>
                ) : null}
            </div>
        </form>
    );
};

export default AddCategoryForm;
