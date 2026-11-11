import { cn } from "app/frontend/lib/utils";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

interface IProps {
    sortMode: "newest" | "alpha" | "score" | "latest_action";
    onSortModeChange: (mode: "newest" | "alpha" | "score" | "latest_action") => void;
}

// @lat: [[bill-interesting-score#Why picker sort controls grow on phones]]
const BillPickerSortToggle: React.FC<IProps> = ({ sortMode, onSortModeChange }) => {
    const segmentClass = (active: boolean) =>
        cn(
            "min-h-11 min-w-11 px-2 py-0.5 text-xs transition-colors md:min-h-0 md:min-w-0 md:px-3 md:py-1.5",
            active ? "bg-muted font-semibold text-foreground" : "bg-transparent font-normal text-muted-foreground",
        );

    return (
        <div className="flex w-full items-center gap-1.5 md:w-auto">
            <div
                data-testid="bill-picker-sort-toggle"
                className="grid min-w-0 flex-1 grid-cols-2 overflow-hidden rounded-lg border-neo border-border-strong md:inline-flex md:w-auto md:flex-none"
            >
                <button
                    type="button"
                    data-testid="sort-newest"
                    aria-pressed={sortMode === "newest"}
                    onClick={() => onSortModeChange("newest")}
                    className={segmentClass(sortMode === "newest")}
                >
                    Newest
                </button>
                <button
                    type="button"
                    data-testid="sort-alpha"
                    aria-pressed={sortMode === "alpha"}
                    onClick={() => onSortModeChange("alpha")}
                    className={cn("border-l border-border-strong", segmentClass(sortMode === "alpha"))}
                >
                    A-Z
                </button>
                <button
                    type="button"
                    data-testid="sort-score"
                    aria-pressed={sortMode === "score"}
                    onClick={() => onSortModeChange("score")}
                    className={cn(
                        "border-t border-border-strong md:border-l md:border-t-0",
                        segmentClass(sortMode === "score"),
                    )}
                >
                    Most Interesting
                </button>
                <button
                    type="button"
                    data-testid="sort-latest-action"
                    aria-pressed={sortMode === "latest_action"}
                    onClick={() => onSortModeChange("latest_action")}
                    className={cn(
                        "border-l border-t border-border-strong md:border-t-0",
                        segmentClass(sortMode === "latest_action"),
                    )}
                >
                    Recent intro/vote
                </button>
            </div>
            <FeatureInfo note="creator.pickerSort" />
        </div>
    );
};

export default BillPickerSortToggle;
