import React, { useState } from "react";
import { Image, Text, View } from "react-native";

import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import type { IFeedLegislator } from "./types";

const LOCALE_ABBREVIATIONS: Record<string, string> = {
    "Baltimore City": "BAL",
    Maryland: "MD",
    "U.S. Congress": "US",
    Congress: "US",
};

const getLocaleAbbreviation = (localeName: string): string => {
    if (LOCALE_ABBREVIATIONS[localeName]) {
        return LOCALE_ABBREVIATIONS[localeName];
    }
    const words = localeName.trim().split(/\s+/);
    if (words.length >= 2) {
        return words
            .slice(0, 3)
            .map((w) => w[0]?.toUpperCase() ?? "")
            .join("");
    }
    return localeName.slice(0, 3).toUpperCase();
};

const getInitials = (name: string): string => {
    const parts = name.trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0] ?? ""}${parts[parts.length - 1][0] ?? ""}`.toUpperCase();
};

export const LocaleTile: React.FC<{ localeName: string }> = ({ localeName }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <View
            style={{
                width: 44,
                height: 44,
                borderRadius: 8,
                backgroundColor: t.surface3,
                alignItems: "center",
                justifyContent: "center",
            }}
        >
            <Text style={{ fontSize: 12, fontWeight: "700", letterSpacing: 0.5, color: t.primary }}>
                {getLocaleAbbreviation(localeName)}
            </Text>
        </View>
    );
};

export const LegislatorAvatar: React.FC<{ legislator: IFeedLegislator }> = ({ legislator }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const [failedUrl, setFailedUrl] = useState<string | null>(null);
    const showImage = Boolean(legislator.photo_url) && failedUrl !== legislator.photo_url;

    if (showImage && legislator.photo_url) {
        return (
            <Image
                source={{ uri: legislator.photo_url }}
                accessibilityLabel={legislator.full_name}
                onError={() => setFailedUrl(legislator.photo_url)}
                style={{
                    width: 44,
                    height: 44,
                    borderRadius: 22,
                    borderWidth: 1,
                    borderColor: t.border,
                    backgroundColor: t.surface2,
                }}
            />
        );
    }

    return (
        <View
            style={{
                width: 44,
                height: 44,
                borderRadius: 22,
                backgroundColor: t.surface2,
                alignItems: "center",
                justifyContent: "center",
            }}
        >
            <Text style={{ fontSize: 14, fontWeight: "600", color: t.mutedForeground }}>
                {getInitials(legislator.full_name)}
            </Text>
        </View>
    );
};

export const OrganizationTile: React.FC<{ name: string }> = ({ name }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <View
            style={{
                width: 44,
                height: 44,
                borderRadius: 8,
                backgroundColor: t.surface2,
                alignItems: "center",
                justifyContent: "center",
            }}
        >
            <Text style={{ fontSize: 12, fontWeight: "700", color: t.foreground }}>{getInitials(name)}</Text>
        </View>
    );
};
