import { buildFilterParams, chipClass } from "app/frontend/components/admin/creator/activity-log/filterParams";
import { Button } from "app/frontend/components/ui/button";
import { ButtonGroup } from "app/frontend/components/ui/button-group";
import type {
    ActivityLogSeverityFilter,
    ActivityLogSubjectFilter,
    ActivityLogWindowFilter,
} from "app/frontend/types/activityLog";

const WINDOW_LABELS: Record<ActivityLogWindowFilter, string> = {
    "24h": "Last 24h",
    "7d": "Last 7 days",
    "30d": "Last 30 days",
    all: "All time",
};

interface IProps {
    currentBillId?: number;
    currentSubject: ActivityLogSubjectFilter;
    currentSeverity: ActivityLogSeverityFilter;
    currentWindow: ActivityLogWindowFilter;
    onFilterChange: (nextParams: Record<string, string>) => void;
}

const ActivityLogFilters: React.FC<IProps> = ({
    currentBillId,
    currentSubject,
    currentSeverity,
    currentWindow,
    onFilterChange,
}) => {
    const current = { subject: currentSubject, severity: currentSeverity, window: currentWindow };

    return (
        <div className="flex flex-wrap gap-2">
            <ButtonGroup>
                <Button
                    variant="outline"
                    size="sm"
                    aria-pressed={currentSubject === "all_bills"}
                    className={chipClass(currentSubject === "all_bills")}
                    onClick={() => onFilterChange(buildFilterParams(current, { subject: "all_bills" }))}
                >
                    All bills
                </Button>
                <Button
                    variant="outline"
                    size="sm"
                    aria-pressed={currentSubject === "this_bill"}
                    className={chipClass(currentSubject === "this_bill")}
                    aria-disabled={!currentBillId ? "true" : undefined}
                    onClick={() => {
                        if (!currentBillId) return;
                        onFilterChange(buildFilterParams(current, { subject: "this_bill" }));
                    }}
                >
                    This bill
                </Button>
            </ButtonGroup>

            <ButtonGroup>
                <Button
                    variant="outline"
                    size="sm"
                    aria-pressed={currentSeverity === "all"}
                    className={chipClass(currentSeverity === "all")}
                    onClick={() => onFilterChange(buildFilterParams(current, { severity: "all" }))}
                >
                    All Severity Levels
                </Button>
                <Button
                    variant="outline"
                    size="sm"
                    aria-pressed={currentSeverity === "errors"}
                    className={chipClass(currentSeverity === "errors")}
                    onClick={() => onFilterChange(buildFilterParams(current, { severity: "errors" }))}
                >
                    Errors only
                </Button>
            </ButtonGroup>

            <ButtonGroup>
                {(["24h", "7d", "30d", "all"] as ActivityLogWindowFilter[]).map((w) => (
                    <Button
                        key={w}
                        variant="outline"
                        size="sm"
                        aria-pressed={currentWindow === w}
                        className={chipClass(currentWindow === w)}
                        onClick={() => onFilterChange(buildFilterParams(current, { window: w }))}
                    >
                        {WINDOW_LABELS[w]}
                    </Button>
                ))}
            </ButtonGroup>
        </div>
    );
};

export default ActivityLogFilters;
