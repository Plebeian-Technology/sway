// @lat: [[mobile-bill-surface-components-design#BillContent]]
import React from "react";
import { View, Text } from "react-native";
import { Markdown } from "./Markdown";

interface BillContentBill {
    id: number;
    title: string;
    summary?: string | null;
    text?: string | null;
    body?: string | null;
}

export interface BillContentProps {
    bill: BillContentBill;
    testID?: string;
}

export function BillContent({ bill, testID }: BillContentProps) {
    const summary = bill.summary?.trim();
    const body = (bill.body ?? bill.text)?.trim();

    return (
        <View testID={testID ?? "bill-content"} className="mt-4">
            {summary ? (
                <View className="mb-4">
                    <Text
                        className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-1"
                        accessibilityRole="header"
                    >
                        Sway summary
                    </Text>
                    <Markdown
                        content={summary}
                        testID="bill-content-summary"
                        className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                    />
                </View>
            ) : null}

            {body ? (
                <View className="mb-2">
                    <Text
                        className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-1"
                        accessibilityRole="header"
                    >
                        Bill text
                    </Text>
                    <Text
                        testID="bill-content-body"
                        className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                        accessibilityRole="text"
                    >
                        {body}
                    </Text>
                </View>
            ) : null}

            {!summary && !body ? (
                <Text
                    testID="bill-content-empty"
                    className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    accessibilityRole="text"
                >
                    Bill text and summary are not yet available.
                </Text>
            ) : null}
        </View>
    );
}

export default BillContent;
