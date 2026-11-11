import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "app/frontend/components/ui/button";

interface IProps {
    page: number;
    pageCount: number;
    onPageChange: (page: number) => void;
    className?: string;
}

const PAGE_WINDOW_SIBLINGS = 1;

const MAX_PAGES_WITHOUT_ELLIPSIS = PAGE_WINDOW_SIBLINGS * 2 + 5;

const ELLIPSIS = "ellipsis";

type PageEntry = number | typeof ELLIPSIS;

const range = (start: number, end: number): number[] =>
    Array.from({ length: end - start + 1 }, (_, index) => start + index);

// @lat: [[pagination#Windowing the page strip]]
const buildPageWindow = (page: number, pageCount: number): PageEntry[] => {
    if (pageCount <= MAX_PAGES_WITHOUT_ELLIPSIS) return range(1, pageCount);

    const leftSibling = Math.max(page - PAGE_WINDOW_SIBLINGS, 1);
    const rightSibling = Math.min(page + PAGE_WINDOW_SIBLINGS, pageCount);
    const showLeftEllipsis = leftSibling > 2;
    const showRightEllipsis = rightSibling < pageCount - 1;
    const edgeRunLength = PAGE_WINDOW_SIBLINGS * 2 + 3;

    if (!showLeftEllipsis && showRightEllipsis) {
        return [...range(1, edgeRunLength), ELLIPSIS, pageCount];
    }
    if (showLeftEllipsis && !showRightEllipsis) {
        return [1, ELLIPSIS, ...range(pageCount - edgeRunLength + 1, pageCount)];
    }
    return [1, ELLIPSIS, ...range(leftSibling, rightSibling), ELLIPSIS, pageCount];
};

const Pagination: React.FC<IProps> = ({ page, pageCount, onPageChange, className }) => {
    if (pageCount <= 1) return null;

    const entries = buildPageWindow(page, pageCount);

    return (
        <nav aria-label="Pagination" className={cn("flex items-center gap-1", className)}>
            <Button
                variant="outline"
                size="icon"
                type="button"
                onClick={() => onPageChange(page - 1)}
                disabled={page <= 1}
                aria-label="Previous page"
            >
                <ChevronLeft aria-hidden />
            </Button>
            {entries.map((entry, index) =>
                entry === ELLIPSIS ? (
                    <span
                        key={`ellipsis-${index}`}
                        aria-hidden="true"
                        className="flex size-11 items-center justify-center text-muted-foreground sm:size-9"
                    >
                        …
                    </span>
                ) : (
                    <Button
                        key={entry}
                        variant={entry === page ? "default" : "outline"}
                        size="icon"
                        type="button"
                        onClick={() => onPageChange(entry)}
                        aria-label={`Page ${entry}`}
                        aria-current={entry === page ? "page" : undefined}
                    >
                        {entry}
                    </Button>
                ),
            )}
            <Button
                variant="outline"
                size="icon"
                type="button"
                onClick={() => onPageChange(page + 1)}
                disabled={page >= pageCount}
                aria-label="Next page"
            >
                <ChevronRight aria-hidden />
            </Button>
        </nav>
    );
};

export default Pagination;
