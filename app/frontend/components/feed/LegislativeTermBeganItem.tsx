import FeedAvatar from "app/frontend/components/feed/FeedAvatar";
import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const LegislativeTermBeganItem: React.FC<IProps> = ({ item }) => {
    const localeName = item.sway_locale?.name ?? "";

    return (
        <FeedItemShell
            item={item}
            avatar={<FeedAvatar kind="locale" localeName={localeName} />}
            whoLine={<strong className="font-semibold">{PARITY_COPY.feed.legislativeTermBegan(localeName)}</strong>}
        />
    );
};

export default LegislativeTermBeganItem;
