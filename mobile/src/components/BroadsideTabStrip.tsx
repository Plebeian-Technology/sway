// @lat: [[mobile-shared-primitives-design#BroadsideTabStrip]]
import React from "react";
import { Pressable, Text, View } from "react-native";

export interface TabItem {
    key: string;
    label: string;
}

export interface BroadsideTabStripProps {
    tabs: TabItem[];
    activeKey: string;
    onChange: (key: string) => void;
    testID?: string;
}

export function BroadsideTabStrip({ tabs, activeKey, onChange, testID }: BroadsideTabStripProps) {
    return (
        <View
            testID={testID ?? "broadside-tab-strip"}
            accessibilityRole="tablist"
            className="flex-row bg-card-light dark:bg-card-dark border-b border-border-light dark:border-border-dark"
        >
            {tabs.map((tab) => {
                const isActive = tab.key === activeKey;
                return (
                    <Pressable
                        key={tab.key}
                        testID={`tab-${tab.key}`}
                        onPress={() => onChange(tab.key)}
                        accessibilityRole="tab"
                        accessibilityState={{ selected: isActive }}
                        accessibilityLabel={tab.label}
                        className="flex-1 items-center py-3"
                        style={{ minHeight: 44 }}
                    >
                        <Text
                            maxFontSizeMultiplier={1.3}
                            numberOfLines={1}
                            adjustsFontSizeToFit
                            minimumFontScale={0.75}
                            className={`text-sm font-open-sans-semibold ${
                                isActive
                                    ? "text-accent-light dark:text-accent-dark"
                                    : "text-muted-foreground-light dark:text-muted-foreground-dark"
                            }`}
                        >
                            {tab.label}
                        </Text>
                        {/* @lat: [[mobile-shared-primitives-design#BroadsideTabStrip#No animation]] */}
                        <View
                            className={`h-[3px] w-full mt-1 ${isActive ? "bg-accent-light dark:bg-accent-dark" : "bg-transparent"}`}
                        />
                    </Pressable>
                );
            })}
        </View>
    );
}

export default BroadsideTabStrip;
