import { Search, X } from "lucide-react";
import { useId } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    value: string;
    onChange: (value: string) => void;
}

const FeedSearchBar: React.FC<IProps> = ({ value, onChange }) => {
    const inputId = useId();

    return (
        <div className="border-b border-border bg-card px-5 py-3.5">
            <label htmlFor={inputId} className="sr-only">
                {PARITY_COPY.feed.searchLabel}
            </label>
            <div className="flex min-h-12 items-center gap-2 rounded-md border border-border bg-input pl-3.5 pr-1 focus-within:border-ring focus-within:bg-card">
                <Search className="size-4.5 shrink-0 text-muted-foreground" aria-hidden="true" />
                <input
                    id={inputId}
                    type="search"
                    value={value}
                    onChange={(event) => onChange(event.target.value)}
                    placeholder={PARITY_COPY.feed.searchPlaceholder}
                    className="min-w-0 flex-1 bg-transparent text-sm text-foreground placeholder:text-muted-foreground focus:outline-none"
                />
                {value.length > 0 && (
                    <button
                        type="button"
                        onClick={() => onChange("")}
                        aria-label={PARITY_COPY.feed.clearSearch}
                        className="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:text-foreground"
                    >
                        <X className="size-4.5" aria-hidden="true" />
                    </button>
                )}
            </div>
        </div>
    );
};

export default FeedSearchBar;
