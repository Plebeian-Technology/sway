// @lat: [[mobile-shared-primitives-design#StampedBadge]]
import React from "react";
import { View, Text } from "react-native";

export interface StampedBadgeProps {
    label: string;
    color: string;
    accessibilityPrefix?: string;
    testID?: string;
}

function linearize(c: number): number {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

function luminance(r: number, g: number, b: number): number {
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b);
}

function contrast(l1: number, l2: number): number {
    const lighter = Math.max(l1, l2);
    const darker = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
}

function parseRGB(color: string): [number, number, number] | null {
    const hex = color.match(/^#([0-9a-f]{6})$/i);
    if (hex) {
        const n = parseInt(hex[1], 16);
        return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
    }
    const rgbMatch = color.match(/^rgb\((\d+)[,\s]+(\d+)[,\s]+(\d+)\)$/i);
    if (rgbMatch) {
        return [parseInt(rgbMatch[1], 10), parseInt(rgbMatch[2], 10), parseInt(rgbMatch[3], 10)];
    }
    return null;
}

// @lat: [[mobile-shared-primitives-design#StampedBadge#readableForeground]]
export function readableForeground(fill: string): "#ffffff" | "#212529" {
    const parsed = parseRGB(fill);
    if (!parsed) return "#ffffff";
    const [r, g, b] = parsed;
    const fillL = luminance(r, g, b);
    const whiteL = 1.0;
    const darkL = luminance(0x21, 0x25, 0x29);
    const contrastWhite = contrast(whiteL, fillL);
    const contrastDark = contrast(darkL, fillL);
    return contrastWhite >= contrastDark ? "#ffffff" : "#212529";
}

export function StampedBadge({ label, color, accessibilityPrefix = "Status", testID }: StampedBadgeProps) {
    return (
        <View
            accessible
            accessibilityRole="text"
            accessibilityLabel={`${accessibilityPrefix}: ${label}`}
            testID={testID ?? "stamped-badge"}
            style={{
                backgroundColor: color,
                borderRadius: 4,
                borderWidth: 1,
                borderColor: color,
                paddingHorizontal: 8,
                paddingVertical: 2,
                alignSelf: "flex-start",
            }}
        >
            <Text
                className="text-sm font-open-sans-semibold"
                style={{ color: readableForeground(color), fontVariant: ["tabular-nums"] }}
            >
                {label}
            </Text>
        </View>
    );
}

export default StampedBadge;
