// @lat: [[admin-categories-controller-design#Categories.tsx, the frontend page]]

import * as React from "react";

import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";

import AddCategoryForm from "app/frontend/components/admin/categories/AddCategoryForm";
import CategoryRow, { type ICategory } from "app/frontend/components/admin/categories/CategoryRow";

interface IProps {
    categories: ICategory[];
}

const Categories: React.FC<IProps> = ({ categories }) => {
    const [editingId, setEditingId] = React.useState<number | null>(null);
    const [renameDraft, setRenameDraft] = React.useState<string>("");

    const handleStartEdit = (id: number, currentName: string) => {
        setEditingId(id);
        setRenameDraft(currentName);
    };

    const handleEndEdit = () => {
        setEditingId(null);
        setRenameDraft("");
    };

    return (
        <div className="mx-auto w-full max-w-4xl space-y-6">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">Category Taxonomy</h1>
                <p className="text-sm text-muted-foreground">
                    Manage categories for bill classification. Changes take effect immediately — no deploy required.
                </p>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle>Categories</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4 p-6">
                    {categories.length === 0 ? (
                        <p className="text-sm text-muted-foreground">No categories found. Add one below.</p>
                    ) : (
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Name</TableHead>
                                    <TableHead>Bills</TableHead>
                                    <TableHead>Status</TableHead>
                                    <TableHead>Actions</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {categories.map((cat) => (
                                    <CategoryRow
                                        key={cat.id}
                                        category={cat}
                                        isEditing={editingId === cat.id}
                                        renameDraft={editingId === cat.id ? renameDraft : ""}
                                        onRenameDraftChange={setRenameDraft}
                                        onStartEdit={handleStartEdit}
                                        onEndEdit={handleEndEdit}
                                    />
                                ))}
                            </TableBody>
                        </Table>
                    )}
                </CardContent>
            </Card>

            <Card>
                <CardHeader>
                    <CardTitle>Add category</CardTitle>
                </CardHeader>
                <CardContent className="p-6">
                    <AddCategoryForm />
                </CardContent>
            </Card>
        </div>
    );
};

export default Categories;
