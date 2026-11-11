import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { FILTER_CHIPS, type FreshnessFilter } from "app/frontend/components/admin/creator/fetched-bills/freshness";

interface IProps {
    query: string;
    filter: FreshnessFilter;
    onQueryChange: (query: string) => void;
    onFilterChange: (filter: FreshnessFilter) => void;
}

const FetchedBillsFilters: React.FC<IProps> = ({ query, filter, onQueryChange, onFilterChange }) => {
    return (
        <div className="flex flex-wrap items-center gap-2">
            <Input
                type="search"
                placeholder="Search external ID or title"
                value={query}
                onChange={(e) => onQueryChange(e.target.value)}
                className="h-11 sm:h-8 w-full sm:max-w-xs text-sm"
                data-testid="fetched-bills-search"
            />
            <fieldset className="flex flex-wrap gap-1 border-0 p-0">
                <legend className="sr-only">Filter by freshness</legend>
                {FILTER_CHIPS.map((chip) => (
                    <Button
                        key={chip.key}
                        type="button"
                        size="xs"
                        variant={filter === chip.key ? "default" : "outline"}
                        aria-pressed={filter === chip.key}
                        onClick={() => onFilterChange(chip.key)}
                        data-testid={`fetched-bills-filter-${chip.key}`}
                        className="min-h-[44px] sm:min-h-0"
                    >
                        {chip.label}
                    </Button>
                ))}
            </fieldset>
        </div>
    );
};

export default FetchedBillsFilters;
