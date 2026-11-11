import { cn } from "app/frontend/lib/utils";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { sway } from "sway";
import { dateToCalendarDay } from "app/frontend/sway_utils/datetimes";

export type CalendarDayState = "empty" | "scheduled-this-bill" | "scheduled-other-bill" | "past" | "outside";

interface IProps {
    day: Date;
    state: CalendarDayState;
    selected?: boolean;
    bill?: sway.IBillPickerOption;
    onSelect: (day: Date) => void;
}

const BillScheduleCalendarDay: React.FC<IProps> = ({ day, state, selected, bill, onSelect }) => {
    const disabled = state === "past" || state === "outside";

    const base =
        "flex h-11 sm:h-10 min-h-11 sm:min-h-10 w-full items-center justify-center rounded-lg text-sm font-semibold tabular-nums lining-nums transition-colors duration-fast focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-0";

    const stateClasses: Record<CalendarDayState, string> = {
        empty: "border-neo border-border-soft text-foreground hover:border-border-strong",
        "scheduled-this-bill":
            "bg-vote-for/12 ring-[length:var(--neo-border-width)] ring-vote-for ring-inset text-vote-for uppercase tracking-wide",
        "scheduled-other-bill":
            "bg-primary/12 ring-[length:var(--neo-border-width)] ring-primary ring-inset text-primary uppercase tracking-wide",
        past: "border-neo border-border-soft text-muted-foreground opacity-50",
        outside: "border-0 text-muted-foreground opacity-40",
    };

    const selectedClass = selected
        ? "outline outline-[length:var(--neo-border-width)] outline-foreground outline-offset-[-3px]"
        : "";

    const label = bill?.title || "No scheduled bill";

    const button = (
        <button
            type="button"
            onClick={() => (disabled ? undefined : onSelect(day))}
            disabled={disabled}
            data-state={state}
            data-selected={selected ? "true" : "false"}
            data-testid={`calendar-day-${dateToCalendarDay(day)}`}
            className={cn(base, stateClasses[state], selectedClass, disabled && "cursor-not-allowed")}
            aria-label={`${day.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })} — ${label}`}
        >
            {day.getDate()}
        </button>
    );

    if (state === "outside") {
        return <div className="pointer-events-none">{button}</div>;
    }

    return (
        <TooltipProvider delayDuration={150}>
            <Tooltip>
                <TooltipTrigger asChild>{button}</TooltipTrigger>
                <TooltipContent>{label}</TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
};

export default BillScheduleCalendarDay;
