// @lat: [[mobile-bill-surface-components-design#BillsSortStrip]]
import React from "react";
import { ScrollView, Text } from "react-native";
import { Pressable } from "./ui/Pressable";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { BillsSortValue } from "../utils/billsList";

export interface BillsSortStripProps {
    value: BillsSortValue;
    onChange: (value: BillsSortValue) => void;
    testID?: string;
}

export function BillsSortStrip({ value, onChange, testID }: BillsSortStripProps) {
    return (
        <ScrollView
            testID={testID ?? "bills-sort-strip"}
            horizontal
            showsHorizontalScrollIndicator={false}
            // @lat: [[mobile-bill-surface-components-design#BillsSortStrip]]
            style={{ flexGrow: 0, flexShrink: 0 }}
            contentContainerStyle={{
                gap: 8,
                paddingHorizontal: 16,
                paddingVertical: 6,
                alignItems: "center",
            }}
            accessibilityLabel={PARITY_COPY.bills.sortLabel}
        >
            {PARITY_COPY.bills.sortOptions.map((option) => {
                const isSelected = option.value === value;
                return (
                    <Pressable
                        key={option.value}
                        onPress={() => onChange(option.value)}
                        variant={isSelected ? "default" : "outline"}
                        accessibilityRole="radio"
                        accessibilityState={{ checked: isSelected, selected: isSelected }}
                        accessibilityLabel={`Sort by ${option.label}`}
                        testID={`sort-${option.value}`}
                    >
                        <Text
                            className={`text-sm font-open-sans-semibold ${
                                isSelected
                                    ? "text-primary-foreground-light dark:text-primary-foreground-dark"
                                    : "text-foreground-light dark:text-foreground-dark"
                            }`}
                        >
                            {option.label}
                        </Text>
                    </Pressable>
                );
            })}
        </ScrollView>
    );
}
