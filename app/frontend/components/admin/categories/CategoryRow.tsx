// @lat: [[admin-categories-frontend-row-and-form#Why AddCategoryForm.tsx uses useForm and CategoryRow.tsx uses router.patch]]

import { router } from "@inertiajs/react";

import { notify } from "app/frontend/sway_utils";

import { categoryRowDomId, scrollToCategoryRow } from "app/frontend/components/admin/categories/categoryRowDom";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { Input } from "app/frontend/components/ui/input";
import { TableCell, TableRow } from "app/frontend/components/ui/table";

export interface ICategory {
    id: number;
    name: string;
    slug: string;
    active: boolean;
    bill_count: number;
}

interface IProps {
    category: ICategory;
    isEditing: boolean;
    renameDraft: string;
    onRenameDraftChange: (draft: string) => void;
    onStartEdit: (id: number, currentName: string) => void;
    onEndEdit: () => void;
}

// @lat: [[inertia-nested-form-errors-accessor#Reading errors from a nested Inertia form]]
const categoryNameError = (errors: unknown): string | undefined => {
    const flat = (errors as Record<string, string | undefined>)["category.name"];
    const nested = (errors as { category?: { name?: string } }).category?.name;
    return flat ?? nested;
};

const CategoryRow: React.FC<IProps> = ({
    category,
    isEditing,
    renameDraft,
    onRenameDraftChange,
    onStartEdit,
    onEndEdit,
}) => {
    const confirm = useConfirm();

    const handleStartRename = () => {
        onStartEdit(category.id, category.name);
    };

    const handleDiscardRename = () => {
        onEndEdit();
    };

    const handleSaveName = () => {
        router.patch(
            `/admin/categories/${category.id}`,
            { category: { name: renameDraft } },
            {
                preserveScroll: true,
                onSuccess: () => {
                    onEndEdit();
                    // @lat: [[admin-categories-frontend-row-and-form#Scrolling to the affected row]]
                    scrollToCategoryRow(category.id);
                },
                // @lat: [[admin-categories-frontend-row-and-form#Toasting refused PATCH/DELETE requests in CategoryRow.tsx]]
                onError: (errors) => {
                    notify({ level: "error", title: categoryNameError(errors) ?? "Rename failed." });
                },
            },
        );
    };

    // @lat: [[admin-categories-frontend-row-and-form#Toasting refused PATCH/DELETE requests in CategoryRow.tsx]]
    const toggleActive = (active: boolean) => {
        router.patch(
            `/admin/categories/${category.id}`,
            { category: { active } },
            {
                preserveScroll: true,
                onError: (errors) =>
                    notify({ level: "error", title: categoryNameError(errors) ?? "Could not update category." }),
            },
        );
    };

    const handleDeactivate = async () => {
        const confirmed = await confirm({
            title: "Deactivate category?",
            description:
                "This removes the category from the taxonomy and the bill filter chips immediately. Existing bill assignments are preserved.",
            confirmLabel: "Deactivate",
            cancelLabel: "Keep active",
            tone: "destructive",
        });
        if (!confirmed) return;
        toggleActive(false);
    };

    const handleActivate = () => {
        toggleActive(true);
    };

    // @lat: [[admin-categories-frontend-row-and-form#Toasting refused PATCH/DELETE requests in CategoryRow.tsx]]
    const handleDelete = async () => {
        const confirmed = await confirm({
            title: "Delete category?",
            description:
                category.bill_count > 0
                    ? `This permanently deletes "${category.name}" and removes it from ${category.bill_count} bill${category.bill_count === 1 ? "" : "s"}. This cannot be undone.`
                    : `This permanently deletes "${category.name}". This cannot be undone.`,
            confirmLabel: "Delete",
            cancelLabel: "Keep",
            tone: "destructive",
        });
        if (!confirmed) return;
        router.delete(`/admin/categories/${category.id}`, {
            preserveScroll: true,
            onError: (errors) =>
                notify({ level: "error", title: categoryNameError(errors) ?? "Could not delete category." }),
        });
    };

    return (
        <TableRow id={categoryRowDomId(category.id)}>
            <TableCell className="w-full">
                {isEditing ? (
                    <div className="flex items-center gap-2">
                        <Input
                            aria-label={`Rename ${category.name}`}
                            className="w-48"
                            value={renameDraft}
                            onChange={(e) => onRenameDraftChange(e.target.value)}
                            onKeyDown={(e) => {
                                if (e.key === "Enter") handleSaveName();
                                if (e.key === "Escape") handleDiscardRename();
                            }}
                        />
                        <Button size="sm" variant="default" onClick={handleSaveName}>
                            Save name
                        </Button>
                        <Button size="sm" variant="ghost" onClick={handleDiscardRename}>
                            Discard rename
                        </Button>
                    </div>
                ) : (
                    <span>{category.name}</span>
                )}
            </TableCell>

            <TableCell className="text-sm text-muted-foreground">{category.bill_count}</TableCell>

            <TableCell>
                {category.active ? (
                    <Badge variant="stamp" tone="success">
                        Active
                    </Badge>
                ) : (
                    <Badge variant="stamp" tone="neutral">
                        Inactive
                    </Badge>
                )}
            </TableCell>

            <TableCell>
                <div className="flex items-center gap-2">
                    <Button size="sm" variant="outline" onClick={handleStartRename}>
                        Rename
                    </Button>
                    {category.active ? (
                        <Button size="sm" variant="outline" onClick={handleDeactivate}>
                            Deactivate
                        </Button>
                    ) : (
                        <>
                            <Button size="sm" variant="outline" onClick={handleActivate}>
                                Activate
                            </Button>
                            <Button size="sm" variant="destructive" onClick={handleDelete}>
                                Delete
                            </Button>
                        </>
                    )}
                </div>
            </TableCell>
        </TableRow>
    );
};

export default CategoryRow;
