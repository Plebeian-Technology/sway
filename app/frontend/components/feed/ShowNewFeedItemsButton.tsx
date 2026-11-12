import { ArrowUp } from "lucide-react";

import { Button } from "app/frontend/components/ui/button";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    newCount: number;
    isCapped: boolean;
    onClick: () => void;
}

const ShowNewFeedItemsButton: React.FC<IProps> = ({ newCount, isCapped, onClick }) => {
    const label = newCount > 0 ? PARITY_COPY.feed.showNewItems(newCount, isCapped) : null;

    return (
        <div aria-live="polite">
            {label && (
                <div className="flex justify-center border-b border-border bg-background px-5 py-3">
                    <Button
                        type="button"
                        variant="secondary"
                        size="sm"
                        className="min-h-11 rounded-full border border-border px-4 text-sm font-medium shadow-sm"
                        onClick={onClick}
                    >
                        <ArrowUp className="size-4" aria-hidden="true" />
                        {label}
                    </Button>
                </div>
            )}
        </div>
    );
};

export default ShowNewFeedItemsButton;
