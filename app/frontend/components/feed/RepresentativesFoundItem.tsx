import { Link } from "@inertiajs/react";
import { MapPin } from "lucide-react";

import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const RepresentativesFoundItem: React.FC<IProps> = ({ item }) => (
    <FeedItemShell
        item={item}
        avatar={
            <div
                aria-hidden="true"
                className="flex size-11 items-center justify-center rounded-full bg-surface-2 text-muted-foreground"
            >
                <MapPin className="size-5" aria-hidden="true" />
            </div>
        }
        whoLine={
            <>
                <strong className="font-semibold">{PARITY_COPY.feed.representativesFoundActor}</strong>{" "}
                {PARITY_COPY.feed.representativesFoundAction}
            </>
        }
    >
        {item.legislators.length > 0 && (
            <ul className="mt-3 space-y-2 border-l-2 border-border pl-3.5 text-sm">
                {item.legislators.map((rep) => (
                    <li key={rep.id}>
                        <div className="font-medium text-foreground">{rep.full_name}</div>
                        {(rep.title || rep.district_name) && (
                            <div className="text-xs text-muted-foreground">
                                {[rep.title, rep.district_name].filter(Boolean).join(", ")}
                            </div>
                        )}
                    </li>
                ))}
            </ul>
        )}

        <div className="mt-4">
            <Link
                href={ROUTES.legislators}
                className="inline-flex min-h-11 items-center justify-center rounded-md border border-border px-3.5 text-sm font-medium text-foreground transition-colors hover:border-border-strong"
            >
                {PARITY_COPY.feed.seeYourRepresentatives}
            </Link>
        </div>
    </FeedItemShell>
);

export default RepresentativesFoundItem;
