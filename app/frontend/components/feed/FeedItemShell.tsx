import { formatItemTimestamp } from "app/frontend/components/feed/dateGrouping";
import type { IFeedItem } from "app/frontend/components/feed/types";

interface IProps {
    item: IFeedItem;
    avatar: React.ReactNode;
    whoLine: React.ReactNode;
    subtitle?: React.ReactNode;
    children?: React.ReactNode;
}

const FeedItemShell: React.FC<IProps> = ({ item, avatar, whoLine, subtitle, children }) => (
    <article className="grid grid-cols-[2.75rem_minmax(0,1fr)] gap-x-3.5 border-b border-border bg-card px-5 py-6">
        <div>{avatar}</div>
        <div className="min-w-0">
            <div className="flex items-baseline justify-between gap-2">
                <p className="m-0 text-base leading-snug text-foreground">{whoLine}</p>
                <span className="shrink-0 whitespace-nowrap text-xs text-muted-foreground">
                    {formatItemTimestamp(item.occurred_at, item.kind)}
                </span>
            </div>
            {subtitle && <div className="mt-1 text-xs text-muted-foreground">{subtitle}</div>}
            {children}
        </div>
    </article>
);

export default FeedItemShell;
