// @lat: [[mobile-admin-area#The categories screen]]
import React, { useState } from "react";
import { ActivityIndicator, Alert, RefreshControl, ScrollView, Text, View } from "react-native";

import { Routes } from "../../api/routes";
import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { FormField } from "../../components/ui/FormField";
import { Pressable } from "../../components/ui/Pressable";
import { useAdminCategories, type AdminCategory } from "../../hooks/admin/useAdminCategories";
import { useAdminMutation } from "../../hooks/admin/useAdminMutation";

const billCountLabel = (count: number) => `${count.toLocaleString()} ${count === 1 ? "bill" : "bills"}`;

const AddCategoryForm = ({ onAdded }: { onAdded: () => void }) => {
    const [name, setName] = useState("");
    const { run, loading, errorMessage } = useAdminMutation("post", Routes.adminCategories());

    const add = async () => {
        const added = await run({ category: { name } });
        if (added === undefined) return;
        setName("");
        onAdded();
    };

    return (
        <Card className="mx-4 mb-3">
            <Text className="mb-3 text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Add category
            </Text>
            <FormField
                testID="admin-category-new-name"
                label="Name"
                value={name}
                onChangeText={setName}
                error={errorMessage ?? undefined}
                disabled={loading}
            />
            <Pressable
                testID="admin-category-add"
                variant="default"
                disabled={loading}
                onPress={() => void add()}
                accessibilityLabel="Add the category"
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Adding..." : "Add category"}
                </Text>
            </Pressable>
        </Card>
    );
};

const CategoryRow = ({ category, onChanged }: { category: AdminCategory; onChanged: () => void }) => {
    const [renaming, setRenaming] = useState(false);
    const [draft, setDraft] = useState(category.name);
    const update = useAdminMutation("patch", Routes.adminCategory(category.id));
    const remove = useAdminMutation("delete", Routes.adminCategory(category.id));
    const busy = update.loading || remove.loading;
    const errorMessage = update.errorMessage ?? remove.errorMessage;

    const saveName = async () => {
        const saved = await update.run({ category: { name: draft } });
        if (saved === undefined) return;
        setRenaming(false);
        onChanged();
    };

    const setActive = async (active: boolean) => {
        const saved = await update.run({ category: { active } });
        if (saved !== undefined) onChanged();
    };

    const confirmDeactivate = () => {
        Alert.alert(
            "Deactivate category?",
            "This removes the category from the taxonomy and the bill filter chips immediately. Existing bill assignments are preserved.",
            [
                { text: "Keep active", style: "cancel" },
                { text: "Deactivate", style: "destructive", onPress: () => void setActive(false) },
            ],
        );
    };

    const deleteCategory = async () => {
        const removed = await remove.run();
        if (removed !== undefined) onChanged();
    };

    const confirmDelete = () => {
        const description =
            category.bill_count > 0
                ? `This permanently deletes "${category.name}" and removes it from ${billCountLabel(category.bill_count)}. This cannot be undone.`
                : `This permanently deletes "${category.name}". This cannot be undone.`;
        Alert.alert("Delete category?", description, [
            { text: "Keep", style: "cancel" },
            { text: "Delete", style: "destructive", onPress: () => void deleteCategory() },
        ]);
    };

    return (
        <View testID={`admin-category-${category.id}`} className="py-2">
            <View className="flex-row items-center justify-between gap-3">
                <View className="flex-1">
                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {category.name}
                    </Text>
                    <Text
                        testID={`admin-category-${category.id}-bills`}
                        className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {billCountLabel(category.bill_count)}
                    </Text>
                </View>
                <Text className="text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                    {category.active ? "Active" : "Inactive"}
                </Text>
            </View>
            {renaming ? (
                <View className="mt-3">
                    <FormField
                        testID={`admin-category-${category.id}-name`}
                        label="Name"
                        value={draft}
                        onChangeText={setDraft}
                        disabled={busy}
                    />
                    <View className="flex-row gap-2">
                        <Pressable
                            testID={`admin-category-${category.id}-save`}
                            variant="default"
                            disabled={busy}
                            onPress={() => void saveName()}
                            accessibilityLabel={`Save the name of ${category.name}`}
                        >
                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                Save name
                            </Text>
                        </Pressable>
                        <Pressable
                            testID={`admin-category-${category.id}-discard`}
                            variant="ghost"
                            disabled={busy}
                            onPress={() => setRenaming(false)}
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                Discard rename
                            </Text>
                        </Pressable>
                    </View>
                </View>
            ) : (
                <View className="mt-2 flex-row flex-wrap gap-2">
                    <Pressable
                        testID={`admin-category-${category.id}-rename`}
                        variant="outline"
                        disabled={busy}
                        onPress={() => {
                            setDraft(category.name);
                            setRenaming(true);
                        }}
                        accessibilityLabel={`Rename ${category.name}`}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Rename
                        </Text>
                    </Pressable>
                    {category.active ? (
                        <Pressable
                            testID={`admin-category-${category.id}-active`}
                            variant="outline"
                            disabled={busy}
                            onPress={confirmDeactivate}
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                Deactivate
                            </Text>
                        </Pressable>
                    ) : (
                        <>
                            <Pressable
                                testID={`admin-category-${category.id}-active`}
                                variant="outline"
                                disabled={busy}
                                onPress={() => void setActive(true)}
                            >
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    Activate
                                </Text>
                            </Pressable>
                            <Pressable
                                testID={`admin-category-${category.id}-delete`}
                                variant="destructive"
                                disabled={busy}
                                onPress={confirmDelete}
                                accessibilityLabel={`Delete ${category.name}`}
                            >
                                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                    Delete
                                </Text>
                            </Pressable>
                        </>
                    )}
                </View>
            )}
            {errorMessage ? (
                <Text
                    testID={`admin-category-${category.id}-error`}
                    className="mt-2 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {errorMessage}
                </Text>
            ) : null}
        </View>
    );
};

export default function CategoriesScreen() {
    const { data, loading, error, refresh } = useAdminCategories();
    const reload = () => {
        void refresh();
    };

    return (
        <ScrollView
            testID="admin-categories-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            keyboardShouldPersistTaps="handled"
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={reload}
                    accessibilityLabel="Pull to refresh the categories"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Category taxonomy
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Manage categories for bill classification. Changes take effect immediately.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-categories-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-categories-loading" className="py-12" />
            ) : (
                <>
                    <Card testID="admin-categories-list" className="mx-4 mb-3">
                        <Text className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Categories
                        </Text>
                        {data.categories.length === 0 ? (
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                No categories found. Add one below.
                            </Text>
                        ) : (
                            data.categories.map((category) => (
                                <CategoryRow key={category.id} category={category} onChanged={reload} />
                            ))
                        )}
                    </Card>
                    <AddCategoryForm onAdded={reload} />
                </>
            )}
        </ScrollView>
    );
}
