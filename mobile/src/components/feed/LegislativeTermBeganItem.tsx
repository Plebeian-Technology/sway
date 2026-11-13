import React from "react";
import { Text } from "react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import FeedAvatar from "./FeedAvatar";
import FeedItemShell from "./FeedItemShell";
import type { IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
}

const LegislativeTermBeganItem: React.FC<IProps> = ({ item }) => {
    const localeName = item.sway_locale?.name ?? "";

    return (
        <FeedItemShell
            item={item}
            avatar={<FeedAvatar kind="locale" localeName={localeName} />}
            whoLine={
                <Text style={{ fontFamily: "OpenSans-SemiBold" }}>
                    {PARITY_COPY.feed.legislativeTermBegan(localeName)}
                </Text>
            }
        />
    );
};

export default LegislativeTermBeganItem;
