import React, { useState } from "react";
import { Image, Text, View } from "react-native";

import { getInitials, getLocaleAbbreviation } from "../../../../app/frontend/components/feed/avatarText";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import type { IFeedLegislator } from "./types";

interface IProps {
    kind: "locale" | "legislator" | "organization";
    localeName?: string;
    legislator?: IFeedLegislator;
    organizationName?: string;
}

const FeedAvatar: React.FC<IProps> = ({ kind, localeName = "", legislator, organizationName = "" }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const [failedUrl, setFailedUrl] = useState<string | null>(null);

    if (kind === "locale") {
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
                <Text
                    style={{
                        fontFamily: "OpenSans-SemiBold",
                        fontSize: 12,
                        letterSpacing: 0.5,
                        color: t.primary,
                    }}
                >
                    {getLocaleAbbreviation(localeName)}
                </Text>
            </View>
        );
    }

    if (kind === "organization") {
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
                <Text style={{ fontFamily: "OpenSans-SemiBold", fontSize: 12, color: t.foreground }}>
                    {getInitials(organizationName)}
                </Text>
            </View>
        );
    }

    const fullName = legislator?.full_name ?? "";
    const photoUrl = legislator?.photo_url ?? null;
    const showImage = Boolean(photoUrl) && failedUrl !== photoUrl;

    if (showImage && photoUrl) {
        return (
            <Image
                source={{ uri: photoUrl }}
                accessibilityLabel={fullName}
                onError={() => setFailedUrl(photoUrl)}
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
            <Text style={{ fontFamily: "OpenSans-SemiBold", fontSize: 14, color: t.mutedForeground }}>
                {getInitials(fullName)}
            </Text>
        </View>
    );
};

export default FeedAvatar;
