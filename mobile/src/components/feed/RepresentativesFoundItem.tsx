import React from "react";
import { Text, View } from "react-native";
import { MapPin } from "lucide-react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { Pressable } from "../ui/Pressable";
import FeedItemShell from "./FeedItemShell";
import type { IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
    onPressLegislators: () => void;
}

const RepresentativesFoundItem: React.FC<IProps> = ({ item, onPressLegislators }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <FeedItemShell
            item={item}
            avatar={
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
                    <MapPin size={20} color={t.mutedForeground} />
                </View>
            }
            whoLine={
                <>
                    <Text style={{ fontWeight: "700" }}>{PARITY_COPY.feed.representativesFoundActor}</Text>{" "}
                    {PARITY_COPY.feed.representativesFoundAction}
                </>
            }
        >
            {item.legislators.length > 0 ? (
                <View
                    style={{
                        marginTop: 12,
                        gap: 8,
                        borderLeftWidth: 2,
                        borderLeftColor: t.border,
                        paddingLeft: 12,
                    }}
                >
                    {item.legislators.map((rep) => (
                        <View key={rep.id}>
                            <Text style={{ fontSize: 14, fontWeight: "600", color: t.foreground }}>
                                {rep.full_name}
                            </Text>
                            {rep.title || rep.district_name ? (
                                <Text style={{ fontSize: 12, color: t.mutedForeground }}>
                                    {[rep.title, rep.district_name].filter(Boolean).join(", ")}
                                </Text>
                            ) : null}
                        </View>
                    ))}
                </View>
            ) : null}

            <View style={{ marginTop: 14, alignItems: "flex-start" }}>
                <Pressable
                    variant="outline"
                    onPress={onPressLegislators}
                    accessibilityLabel={PARITY_COPY.feed.seeYourRepresentatives}
                    className="!rounded-md !px-3.5"
                >
                    <Text style={{ fontSize: 14, fontWeight: "600", color: t.accent }}>
                        {PARITY_COPY.feed.seeYourRepresentatives}
                    </Text>
                </Pressable>
            </View>
        </FeedItemShell>
    );
};

export default RepresentativesFoundItem;
