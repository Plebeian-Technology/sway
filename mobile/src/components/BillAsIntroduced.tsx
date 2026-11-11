// @lat: [[mobile-bill-surface-components-design#BillAsIntroduced]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Pressable } from "./ui/Pressable";
import { hasMoreThanHeadline } from "../utils/billTitle";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const COLLAPSED_LINES = 4;
// Characters; titles at or under this length are never clamped
const FOLD_ABOVE_CHARS = 120;

export interface BillAsIntroducedProps {
    title: string;
    testID?: string;
}

export function BillAsIntroduced({ title, testID }: BillAsIntroducedProps) {
    const [expanded, setExpanded] = useState(false);

    if (!hasMoreThanHeadline(title)) return null;

    const foldable = title.length > FOLD_ABOVE_CHARS;

    return (
        <View
            testID={testID ?? "bill-as-introduced"}
            className="rounded-xl bg-surface-2-light dark:bg-surface-2-dark px-4 py-4"
        >
            <Text
                className="text-xs font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark"
                style={{ letterSpacing: 1.5 }}
                accessibilityRole="header"
            >
                {PARITY_COPY.bill.asIntroduced}
            </Text>
            <Text
                selectable
                numberOfLines={foldable && !expanded ? COLLAPSED_LINES : undefined}
                className="mt-2 text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                accessibilityRole="text"
            >
                {title}
            </Text>
            {foldable ? (
                <Pressable
                    variant="ghost"
                    onPress={() => setExpanded((v) => !v)}
                    accessibilityLabel={expanded ? PARITY_COPY.bill.showLess : PARITY_COPY.bill.showMore}
                    accessibilityRole="button"
                    accessibilityState={{ expanded }}
                >
                    <Text className="text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark">
                        {expanded ? PARITY_COPY.bill.showLess : PARITY_COPY.bill.showMore}
                    </Text>
                </Pressable>
            ) : null}
        </View>
    );
}

export default BillAsIntroduced;
