import { useState } from "react";
import { router, usePage } from "@inertiajs/react";
import { notify } from "app/frontend/sway_utils";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import { Badge } from "app/frontend/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";

// @lat: [[bill-category-redirect-prop-freshness#Why BillCategoryOverride reads props directly, with no prop drilling or useEffect]]

interface CategoryItem {
    id: number;
    name: string;
    // @lat: [[bill-category-redirect-prop-freshness#Why the active-category counter only counts ACTIVE categories, and stays open when the limit prop is missing]]
    active?: boolean;
}

interface IBillCategoryOverridePageProps {
    bill?: {
        id?: number | null;
        override_categories?: CategoryItem[];
    };
    active_categories?: CategoryItem[];
    // @lat: [[bill-category-redirect-prop-freshness#Why the active-category counter only counts ACTIVE categories, and stays open when the limit prop is missing]]
    max_active_categories_per_bill?: number;
    [key: string]: unknown;
}

// @lat: [[bill-category-redirect-prop-freshness#Why BillCategoryOverride reads props directly, with no prop drilling or useEffect]]
const BillCategoryOverride: React.FC = () => {
    const { props } = usePage<IBillCategoryOverridePageProps>();
    const [selectNonce, setSelectNonce] = useState(0);
    const bill = props.bill;
    const billId = bill?.id;
    const overrideCategories: CategoryItem[] = bill?.override_categories ?? [];
    const activeCategories: CategoryItem[] = props.active_categories ?? [];

    const availableCategories = activeCategories.filter((ac) => !overrideCategories.some((oc) => oc.id === ac.id));

    // @lat: [[bill-category-redirect-prop-freshness#Why the active-category counter only counts ACTIVE categories, and stays open when the limit prop is missing]]
    const activeAssignedCount = overrideCategories.filter((c) => c.active).length;
    const maxActive = props.max_active_categories_per_bill;
    const atMax = maxActive !== undefined && activeAssignedCount >= maxActive;

    const handleRemove = (categoryId: number) => {
        // @lat: [[bill-category-redirect-prop-freshness#Why remove/add use preserveScroll and check pageExpired before toasting]]
        router.delete(`/bills/${billId}/categories/${categoryId}`, {
            preserveScroll: true,
            onSuccess: (page) => {
                if (pageExpired(page)) return;
                notify({ level: "success", title: "Category removed" });
            },
            onError: () => notify({ level: "error", title: "Could not remove category." }),
        });
    };

    const handleAdd = (categoryId: string) => {
        // @lat: [[bill-category-redirect-prop-freshness#Why remove/add use preserveScroll and check pageExpired before toasting]]
        router.post(
            `/bills/${billId}/categories`,
            { category_id: Number(categoryId) },
            {
                preserveScroll: true,
                onSuccess: (page) => {
                    if (pageExpired(page)) return;
                    notify({ level: "success", title: "Category added" });
                },
                onError: () => {
                    setSelectNonce((n) => n + 1);
                    notify({ level: "error", title: "Could not add category." });
                },
            },
        );
    };

    return (
        <div className="flex flex-col gap-4">
            {/* @lat: [[bill-category-redirect-prop-freshness#Why category chips have no removal confirmation]] */}
            {overrideCategories.length === 0 ? (
                <p className="text-sm text-muted-foreground">No categories assigned yet. Add one below.</p>
            ) : (
                <div className="flex flex-wrap gap-2">
                    {overrideCategories.map((cat) => (
                        <Badge key={cat.id} variant="stamp" tone="primary" className="items-center">
                            {cat.name}
                            <button
                                type="button"
                                className="-my-1 ml-1 inline-flex min-h-11 min-w-8 items-center justify-center rounded-full opacity-60 hover:bg-muted/50 hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring sm:min-h-0 sm:min-w-0 sm:size-6"
                                aria-label={`Remove ${cat.name}`}
                                onClick={() => handleRemove(cat.id)}
                            >
                                ×
                            </button>
                        </Badge>
                    ))}
                </div>
            )}

            {atMax ? (
                <p className="text-sm text-muted-foreground">Maximum {maxActive} categories assigned.</p>
            ) : (
                availableCategories.length > 0 && (
                    // @lat: [[phase-60-advisory-resolutions#Select Remount on Failed Category Override]]
                    <Select key={`${overrideCategories.length}-${selectNonce}`} onValueChange={handleAdd}>
                        <SelectTrigger size="sm" className="w-full sm:w-72" aria-label="Add category">
                            <SelectValue placeholder="Select a category…" />
                        </SelectTrigger>
                        <SelectContent>
                            {availableCategories.map((cat) => (
                                <SelectItem key={cat.id} value={String(cat.id)}>
                                    {cat.name}
                                </SelectItem>
                            ))}
                        </SelectContent>
                    </Select>
                )
            )}
        </div>
    );
};

export default BillCategoryOverride;
