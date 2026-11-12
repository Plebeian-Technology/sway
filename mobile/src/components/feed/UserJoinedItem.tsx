import React from "react";
import { Image, Text } from "react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import FeedItemShell from "./FeedItemShell";
import type { IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
}

const UserJoinedItem: React.FC<IProps> = ({ item }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <FeedItemShell
            item={item}
            avatar={
                <Image
                    // oxlint-disable-next-line @typescript-eslint/no-require-imports
                    source={require("../../../assets/sway-logo.png")}
                    accessibilityLabel="Sway"
                    resizeMode="cover"
                    style={{ width: 44, height: 44, borderRadius: 10 }}
                />
            }
            whoLine={
                <>
                    <Text style={{ fontWeight: "700" }}>{PARITY_COPY.feed.userJoinedActor}</Text>{" "}
                    {PARITY_COPY.feed.userJoinedAction}
                </>
            }
        >
            <Text style={{ marginTop: 8, fontSize: 14, lineHeight: 20, color: t.mutedForeground }}>
                {PARITY_COPY.feed.userJoinedSummary}
            </Text>
        </FeedItemShell>
    );
};

export default UserJoinedItem;
