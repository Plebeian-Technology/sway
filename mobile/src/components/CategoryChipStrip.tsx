import React, { useCallback, useMemo, useState } from "react";
import { FlatList, Modal, Pressable as RNPressable, Text, TextInput, View } from "react-native";
import { Pressable } from "./ui/Pressable";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { pressFeedback } from "../theme/effects";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

// @lat: [[bills-category-filter#What the phone shows instead]]
function titleize(s: string): string {
    if (!s) return "";
    return s
        .toLowerCase()
        .split(" ")
        .filter(Boolean)
        .map((word) => word[0].toUpperCase() + word.slice(1))
        .join(" ");
}

export interface CategoryChipStripProps {
    categories: readonly string[];
    selected: string[];
    onToggle: (category: string) => void;
    // @lat: [[bills-category-filter#What the phone shows instead]]
    onClear?: () => void;
    testID?: string;
}

// @lat: [[bills-category-filter#What the phone shows instead]]
export function CategoryChipStrip({ categories, selected, onToggle, onClear, testID }: CategoryChipStripProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const [open, setOpen] = useState(false);
    const [query, setQuery] = useState("");

    const close = useCallback(() => {
        setOpen(false);
        setQuery("");
    }, []);

    const visible = useMemo(() => {
        const needle = query.trim().toLowerCase();
        return needle ? categories.filter((category) => category.toLowerCase().includes(needle)) : categories;
    }, [categories, query]);

    const handleClear = useCallback(() => {
        if (onClear) {
            onClear();
            return;
        }
        selected.forEach((category) => onToggle(category));
    }, [onClear, onToggle, selected]);

    const count = selected.length;
    const triggerLabel = `${PARITY_COPY.bills.categoriesLabel}, ${count > 0 ? `${count} selected` : "none selected"}`;

    return (
        <View className="px-4 pb-3">
            <Pressable
                testID={testID ?? "category-chip-strip"}
                onPress={() => setOpen(true)}
                variant="outline"
                accessibilityRole="button"
                accessibilityState={{ expanded: open }}
                accessibilityLabel={triggerLabel}
                className="flex-row w-full justify-between py-2"
            >
                <View className="flex-row items-center gap-2">
                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {PARITY_COPY.bills.categoriesLabel}
                    </Text>
                    {count > 0 ? (
                        <View
                            testID="category-filter-count"
                            className="rounded-full px-2 py-0.5 bg-accent-light dark:bg-accent-dark"
                        >
                            <Text className="text-xs font-open-sans-semibold" style={{ color: "white" }}>
                                {String(count)}
                            </Text>
                        </View>
                    ) : null}
                </View>
                <Text className="text-xl font-open-sans-semibold text-accent-light dark:text-accent-dark">{"›"}</Text>
            </Pressable>

            <Modal
                visible={open}
                transparent
                animationType="slide"
                accessibilityViewIsModal
                onRequestClose={close}
                testID="category-filter-modal"
            >
                <RNPressable
                    testID="category-filter-scrim"
                    accessibilityLabel={`Close ${PARITY_COPY.bills.categoriesLabel.toLowerCase()}`}
                    style={{ flex: 1, backgroundColor: t.scrim }}
                    onPress={close}
                >
                    <View
                        testID="category-filter-sheet"
                        onStartShouldSetResponder={() => true}
                        className="absolute bottom-0 left-0 right-0 bg-card-light dark:bg-card-dark rounded-t-lg pb-8"
                        style={{ maxHeight: "80%" }}
                    >
                        <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark px-4 pt-4 pb-2">
                            {PARITY_COPY.bills.categoriesLabel}
                        </Text>

                        <View className="px-4 pb-2">
                            <TextInput
                                value={query}
                                onChangeText={setQuery}
                                placeholder={PARITY_COPY.bills.categoryFilterPlaceholder}
                                accessibilityLabel={PARITY_COPY.bills.categoryFilterPlaceholder}
                                autoCapitalize="none"
                                autoCorrect={false}
                                className="border border-border-light dark:border-border-dark rounded-md px-4 py-3 bg-input-light dark:bg-input-dark font-open-sans-light text-foreground-light dark:text-foreground-dark"
                                style={{ minHeight: 44 }}
                                testID="category-filter-search"
                            />
                        </View>

                        <FlatList
                            testID="category-filter-options"
                            data={visible}
                            keyExtractor={(item) => item}
                            keyboardShouldPersistTaps="handled"
                            ListEmptyComponent={
                                <Text
                                    testID="category-filter-empty"
                                    className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark px-4 py-3"
                                >
                                    {PARITY_COPY.bills.noCategoriesFound}
                                </Text>
                            }
                            renderItem={({ item }) => {
                                const isSelected = selected.includes(item);
                                return (
                                    <RNPressable
                                        testID={`chip-${item}`}
                                        onPress={() => onToggle(item)}
                                        accessibilityRole="checkbox"
                                        accessibilityState={{ checked: isSelected }}
                                        accessibilityLabel={`${isSelected ? "Remove" : "Add"} ${item} filter`}
                                        className="flex-row items-center justify-between px-4 py-3 border-b border-border-soft-light dark:border-border-soft-dark"
                                        style={({ pressed }) => [{ minHeight: 44 }, pressFeedback(pressed)]}
                                    >
                                        <Text className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                            {titleize(item)}
                                        </Text>
                                        <Text
                                            testID={`category-check-${item}`}
                                            className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                                        >
                                            {isSelected ? "✓" : ""}
                                        </Text>
                                    </RNPressable>
                                );
                            }}
                        />

                        <View className="flex-row items-center justify-between gap-3 px-4 pt-3">
                            {count > 0 ? (
                                <Pressable
                                    testID="category-filter-clear"
                                    onPress={handleClear}
                                    variant="ghost"
                                    accessibilityLabel={PARITY_COPY.bills.clearCategoriesLabel}
                                >
                                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                        {PARITY_COPY.bills.clearCategoriesLabel}
                                    </Text>
                                </Pressable>
                            ) : (
                                <View />
                            )}
                            <Pressable testID="category-filter-done" onPress={close} accessibilityLabel="Done">
                                <Text className="text-base font-open-sans-semibold" style={{ color: "white" }}>
                                    Done
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                </RNPressable>
            </Modal>
        </View>
    );
}
