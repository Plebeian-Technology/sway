// @lat: [[mobile-bill-surface-components-design#BillHeader]]
import React from "react";
import { View, Text, Pressable } from "react-native";

import { BillVoteStatus } from "./BillVoteStatus";
import { StampedBadge } from "./StampedBadge";
import { useTheme } from "../theme/ThemeProvider";
import { billHeadline } from "../utils/billTitle";
import { billStatusColor, billStatusLabel } from "../utils/billStatus";
import type { BillVoteDates } from "../utils/billVoteStatus";

interface BillHeaderBill extends BillVoteDates {
    id: number;
    bill_number?: string;
    external_id?: string;
    title: string;
    headline?: string;
    chamber?: string;
    status?: string;
    status_color?: string;
    categories?: string[];
    active?: boolean;
}

interface BillHeaderSponsor {
    full_name?: string;
}

export interface BillHeaderProps {
    bill: BillHeaderBill;
    sponsor?: BillHeaderSponsor | null;
    formattedSwayLocaleName?: string;
    // @lat: [[mobile-bill-surface-components-design#BillHeader]]
    hero?: boolean;
    // @lat: [[mobile-bill-surface-components-design#BillHeader]]
    showVoteStatus?: boolean;
    // @lat: [[mobile-bill-surface-components-design#BillHeader]]
    onSponsorPress?: () => void;
    testID?: string;
}

const capitalise = (name: string): string => name.charAt(0).toUpperCase() + name.slice(1);

export function BillHeader({
    bill,
    sponsor,
    formattedSwayLocaleName,
    hero = false,
    showVoteStatus = true,
    onSponsorPress,
    testID,
}: BillHeaderProps) {
    const { colorScheme } = useTheme();
    const billNumber = bill.bill_number ?? bill.external_id ?? null;
    const titleSizeClass = hero ? "text-3xl" : "text-xl";
    const headline = bill.headline ?? billHeadline(bill.title);
    const statusColor = bill.status_color ?? billStatusColor(bill.status, colorScheme);
    const categories = bill.categories ?? [];
    const sponsorName = sponsor?.full_name;
    const sponsorLabel = sponsorName
        ? `Sponsored by ${sponsorName}${formattedSwayLocaleName ? `, ${formattedSwayLocaleName}` : ""}`
        : null;
    const sponsorTextClass = "text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";

    return (
        <View testID={testID ?? "bill-header"}>
            {billNumber ? (
                <Text
                    className="text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mb-1 uppercase"
                    style={{ fontVariant: ["tabular-nums"], letterSpacing: 1.5 }}
                    accessibilityRole="text"
                    accessibilityLabel={`Bill number ${billNumber}${bill.chamber ? `, ${bill.chamber}` : ""}`}
                >
                    {billNumber}
                    {bill.chamber ? ` · ${bill.chamber}` : ""}
                </Text>
            ) : null}

            <Text
                testID="bill-header-title"
                className={`${titleSizeClass} font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-2 leading-tight`}
                accessibilityRole="header"
            >
                {headline}
            </Text>

            {categories.length > 0 ? (
                <View testID="bill-header-categories" className="flex-row flex-wrap gap-2 mb-2">
                    {categories.map((category) => (
                        <View
                            key={category}
                            testID={`bill-header-category-${category}`}
                            className="bg-surface-2-light dark:bg-surface-2-dark px-2 py-0.5 rounded"
                        >
                            <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                {capitalise(category)}
                            </Text>
                        </View>
                    ))}
                </View>
            ) : null}

            {sponsorName && onSponsorPress ? (
                <Pressable
                    testID="bill-header-sponsor"
                    onPress={onSponsorPress}
                    accessibilityRole="link"
                    accessibilityLabel={sponsorLabel ?? undefined}
                    className="mb-1 self-start justify-center"
                    style={{ minHeight: 44 }}
                >
                    <Text className={sponsorTextClass}>
                        Sponsored by{" "}
                        <Text className="font-open-sans-semibold text-accent-light dark:text-accent-dark underline">
                            {sponsorName}
                        </Text>
                        {formattedSwayLocaleName ? ` · ${formattedSwayLocaleName}` : ""}
                    </Text>
                </Pressable>
            ) : sponsorName ? (
                <Text
                    className={`${sponsorTextClass} mb-2`}
                    accessibilityRole="text"
                    accessibilityLabel={sponsorLabel ?? undefined}
                >
                    Sponsored by {sponsorName}
                    {formattedSwayLocaleName ? ` · ${formattedSwayLocaleName}` : ""}
                </Text>
            ) : null}

            {bill.status && statusColor ? (
                <View className="mt-2">
                    <StampedBadge
                        label={billStatusLabel(bill.status)}
                        color={statusColor}
                        testID="bill-header-status"
                    />
                </View>
            ) : null}

            {showVoteStatus ? <BillVoteStatus bill={bill} /> : null}
        </View>
    );
}

export default BillHeader;
