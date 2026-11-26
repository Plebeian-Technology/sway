// @lat: [[mobile-bill-creator#Sections#The category override section]]
import React from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";

interface OverrideCategory {
    id: number;
    name: string;
    active: boolean;
}

interface ActiveCategory {
    id: number;
    name: string;
}

interface CategoryChipProps {
    billId: number;
    category: OverrideCategory;
    refresh: () => Promise<void>;
}

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";

const CategoryChip: React.FC<CategoryChipProps> = ({ billId, category, refresh }) => {
    const testID = `admin-category-${category.id}`;
    const { run, loading, errorMessage } = useAdminMutation<unknown>(
        "delete",
        Routes.billCategory(billId, category.id),
    );

    const remove = async () => {
        if ((await run()) === undefined) return;
        await refresh();
    };

    return (
        <View className="gap-1">
            <View
                testID={testID}
                className="flex-row items-center gap-1 rounded-lg border border-border-light dark:border-border-dark pl-3"
            >
                <Text className={labelText}>{category.name}</Text>
                <Pressable
                    testID={`${testID}-remove`}
                    variant="ghost"
                    disabled={loading}
                    accessibilityLabel={`Remove ${category.name}`}
                    onPress={() => void remove()}
                >
                    <Text className={labelText}>×</Text>
                </Pressable>
            </View>
            {errorMessage ? (
                <Text testID={`${testID}-remove-error`} accessibilityRole="alert" className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
        </View>
    );
};

const CategoryOverrideSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const { run, loading, errorMessage } = useAdminMutation<unknown>("post", Routes.billCategories(billId ?? 0));
    const bill = data.bill as { bill_llm_provisioning?: unknown; override_categories?: OverrideCategory[] } | undefined;

    if (billId === null || !bill?.bill_llm_provisioning) return null;

    const assigned = bill.override_categories ?? [];
    const activeCategories = (data.active_categories as ActiveCategory[] | undefined) ?? [];
    const maxActive = data.max_active_categories_per_bill as number | undefined;
    const available = activeCategories.filter((candidate) => !assigned.some((chip) => chip.id === candidate.id));
    const atMax = maxActive !== undefined && assigned.filter((chip) => chip.active).length >= maxActive;

    const add = async (categoryId: number) => {
        if ((await run({ category_id: categoryId })) === undefined) return;
        await refresh();
    };

    return (
        <View testID="admin-categories" className="px-4 mt-6 gap-3">
            <Text className={labelText}>Categories</Text>
            {assigned.length === 0 ? (
                <Text testID="admin-categories-empty" className={mutedText}>
                    No categories assigned yet. Add one below.
                </Text>
            ) : (
                <View className="flex-row flex-wrap gap-2">
                    {assigned.map((category) => (
                        <CategoryChip key={category.id} billId={billId} category={category} refresh={refresh} />
                    ))}
                </View>
            )}
            {atMax ? (
                <Text testID="admin-categories-max" className={mutedText}>
                    {`Maximum ${maxActive} categories assigned.`}
                </Text>
            ) : available.length > 0 ? (
                <View testID="admin-categories-add" className="gap-2">
                    <Text className={mutedText}>Add category</Text>
                    <View className="flex-row flex-wrap gap-2">
                        {available.map((category) => (
                            <Pressable
                                key={category.id}
                                testID={`admin-category-add-${category.id}`}
                                variant="outline"
                                disabled={loading}
                                accessibilityLabel={`Add ${category.name}`}
                                onPress={() => void add(category.id)}
                            >
                                <Text className={labelText}>{category.name}</Text>
                            </Pressable>
                        ))}
                    </View>
                </View>
            ) : null}
            {errorMessage ? (
                <Text testID="admin-categories-add-error" accessibilityRole="alert" className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
        </View>
    );
};

export default CategoryOverrideSection;
