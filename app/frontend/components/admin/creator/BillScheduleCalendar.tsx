import { usePage } from "@inertiajs/react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useMemo, useState } from "react";
import { sway } from "sway";
import { cn } from "@/lib/utils";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { calendarDayToDate, dateToCalendarDay } from "app/frontend/sway_utils/datetimes";
import BillScheduleCalendarDay, {
    CalendarDayState,
} from "app/frontend/components/admin/creator/BillScheduleCalendarDay";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { useTime } from "app/frontend/hooks/useTime";

const WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] as const;

const daysInMonth = (month: number, year: number) => new Date(year, month + 1, 0).getDate();
const firstWeekday = (month: number, year: number) => new Date(year, month, 1).getDay();

const isSameDay = (a: Date, b: Date) =>
    a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

interface IProps {
    selectedBillId: number | null;
    selectedDate: Date | null;
    onSelectDate: (day: Date, bill: sway.IBillPickerOption | undefined) => void;
}

interface IPageProps {
    bills: sway.IBillPickerOption[];
    [key: string]: unknown;
}

// @lat: [[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]
const BillScheduleCalendar: React.FC<IProps> = ({ selectedBillId, selectedDate, onSelectDate }) => {
    const bills = usePage<IPageProps>().props.bills;

    const now = useTime();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const [month, setMonth] = useState<number>(selectedDate ? selectedDate.getMonth() : now.getMonth());
    const [year, setYear] = useState<number>(selectedDate ? selectedDate.getFullYear() : now.getFullYear());

    const selectedDateKey = selectedDate
        ? `${selectedDate.getFullYear()}-${selectedDate.getMonth()}-${selectedDate.getDate()}`
        : null;
    const [prevSelectedKey, setPrevSelectedKey] = useState<string | null>(selectedDateKey);

    if (selectedDateKey !== prevSelectedKey) {
        setPrevSelectedKey(selectedDateKey);
        if (selectedDate) {
            setMonth(selectedDate.getMonth());
            setYear(selectedDate.getFullYear());
        }
    }

    const billsByDay = useMemo(() => {
        const m = new Map<string, sway.IBillPickerOption>();
        for (const b of bills) {
            if (!b.scheduled_release_date_utc) continue;
            const d = calendarDayToDate(b.scheduled_release_date_utc);
            if (d.getMonth() !== month || d.getFullYear() !== year) continue;
            m.set(d.toDateString(), b);
        }
        return m;
    }, [bills, month, year]);

    const handlePrev = () => {
        if (month === 0) {
            setMonth(11);
            setYear(year - 1);
        } else {
            setMonth(month - 1);
        }
    };
    const handleNext = () => {
        if (month === 11) {
            setMonth(0);
            setYear(year + 1);
        } else {
            setMonth(month + 1);
        }
    };
    const handleToday = () => {
        const current = new Date();
        setMonth(current.getMonth());
        setYear(current.getFullYear());
    };

    const [viewMode, setViewMode] = useState<"month" | "agenda">("month");

    const deriveState = (d: Date): CalendarDayState => {
        if (d.getMonth() !== month) return "outside";
        if (d < today) return "past";
        const scheduled = billsByDay.get(d.toDateString());
        if (!scheduled) return "empty";
        if (selectedBillId && scheduled.id === selectedBillId) return "scheduled-this-bill";
        return "scheduled-other-bill";
    };

    const monthName = new Date(year, month).toLocaleString("default", { month: "long" });

    const cells: Array<{ date: Date; state: CalendarDayState; bill?: sway.IBillPickerOption }> = [];
    const totalDays = daysInMonth(month, year);
    const leadingBlanks = firstWeekday(month, year);

    const prevMonth = month === 0 ? 11 : month - 1;
    const prevYear = month === 0 ? year - 1 : year;
    const prevMonthDays = daysInMonth(prevMonth, prevYear);
    for (let i = leadingBlanks - 1; i >= 0; i--) {
        const d = new Date(prevYear, prevMonth, prevMonthDays - i);
        cells.push({ date: d, state: "outside" });
    }
    for (let i = 1; i <= totalDays; i++) {
        const d = new Date(year, month, i);
        const bill = billsByDay.get(d.toDateString());
        cells.push({ date: d, state: deriveState(d), bill });
    }
    while (cells.length % 7 !== 0) {
        const last = cells[cells.length - 1].date;
        const next = new Date(last.getFullYear(), last.getMonth(), last.getDate() + 1);
        cells.push({ date: next, state: "outside" });
    }

    const monthDays = cells.filter((c) => c.state !== "outside");

    return (
        <div className="rounded-xl border-neo border-border-strong bg-card p-2 shadow-neo sm:p-4">
            <div className="flex flex-wrap items-center justify-between gap-2 pb-3">
                <div className="flex flex-wrap items-center gap-1">
                    <Button
                        variant="outline"
                        size="icon"
                        type="button"
                        onClick={handlePrev}
                        aria-label="Previous month"
                        className="size-11 sm:size-9"
                    >
                        <ChevronLeft aria-hidden />
                    </Button>
                    <div className="flex items-center gap-1.5 px-1">
                        <div className="text-xs font-semibold uppercase tracking-widest tabular-nums lining-nums sm:text-sm">
                            {monthName} {year}
                        </div>
                        <FeatureInfo note="schedule.calendar" />
                    </div>
                    <Button
                        variant="outline"
                        size="icon"
                        type="button"
                        onClick={handleNext}
                        aria-label="Next month"
                        className="size-11 sm:size-9"
                    >
                        <ChevronRight aria-hidden />
                    </Button>
                    <Button
                        variant="outline"
                        size="sm"
                        type="button"
                        onClick={handleToday}
                        className="h-11 min-h-[44px] text-xs sm:h-8 sm:min-h-0"
                        data-testid="btn-calendar-today"
                    >
                        Today
                    </Button>
                </div>

                <fieldset className="flex items-center gap-1 border-0 p-0" aria-label="Schedule view">
                    <Button
                        type="button"
                        size="sm"
                        variant={viewMode === "month" ? "default" : "outline"}
                        onClick={() => setViewMode("month")}
                        className="h-11 min-h-[44px] text-xs sm:h-8 sm:min-h-0"
                        aria-pressed={viewMode === "month"}
                        data-testid="view-mode-month"
                    >
                        Month
                    </Button>
                    <Button
                        type="button"
                        size="sm"
                        variant={viewMode === "agenda" ? "default" : "outline"}
                        onClick={() => setViewMode("agenda")}
                        className="h-11 min-h-[44px] text-xs sm:h-8 sm:min-h-0"
                        aria-pressed={viewMode === "agenda"}
                        data-testid="view-mode-agenda"
                    >
                        Agenda
                    </Button>
                </fieldset>
            </div>

            {viewMode === "agenda" ? (
                <div className="flex flex-col gap-2 divide-y divide-border-soft" data-testid="agenda-view-list">
                    {monthDays.map(({ date, state, bill }) => {
                        const selected = selectedDate ? isSameDay(date, selectedDate) : false;
                        const disabled = state === "past";
                        const dateStr = dateToCalendarDay(date);
                        const formattedDate = date.toLocaleDateString("en-US", {
                            weekday: "short",
                            month: "short",
                            day: "numeric",
                        });

                        return (
                            <div
                                key={dateStr}
                                data-testid={`agenda-row-${dateStr}`}
                                className={cn(
                                    "flex flex-col gap-2 pt-3 first:pt-0 sm:flex-row sm:items-center sm:justify-between",
                                    selected && "rounded-lg bg-accent/20 p-2",
                                    disabled && "opacity-50",
                                )}
                            >
                                <div className="flex min-w-0 flex-1 flex-col gap-1">
                                    <div className="flex items-center gap-2">
                                        <span className="text-sm font-semibold tabular-nums lining-nums">
                                            {formattedDate}
                                        </span>
                                        {state === "scheduled-this-bill" && (
                                            <Badge variant="stamp" tone="success">
                                                This bill
                                            </Badge>
                                        )}
                                        {state === "scheduled-other-bill" && (
                                            <Badge variant="stamp" tone="primary">
                                                Scheduled
                                            </Badge>
                                        )}
                                        {state === "empty" && (
                                            <Badge variant="stamp" tone="neutral">
                                                Available
                                            </Badge>
                                        )}
                                        {state === "past" && (
                                            <Badge variant="stamp" tone="neutral">
                                                Past
                                            </Badge>
                                        )}
                                    </div>
                                    {bill && (
                                        <p className="line-clamp-2 wrap-break-word text-xs text-muted-foreground">
                                            <span className="font-semibold text-foreground">{bill.external_id}:</span>{" "}
                                            {bill.title}
                                        </p>
                                    )}
                                </div>
                                <Button
                                    type="button"
                                    variant={selected ? "default" : "outline"}
                                    size="sm"
                                    disabled={disabled}
                                    onClick={() => (disabled ? undefined : onSelectDate(date, bill))}
                                    data-testid={`btn-select-agenda-date-${dateStr}`}
                                    className="min-h-[44px] w-full sm:min-h-9 sm:w-auto"
                                >
                                    {bill ? "Select bill" : "Select date"}
                                </Button>
                            </div>
                        );
                    })}
                </div>
            ) : (
                <div className="w-full overflow-x-auto">
                    <div className="min-w-[280px]">
                        <div className="grid grid-cols-7 gap-1 pb-1 text-center text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                            {WEEKDAYS.map((w) => (
                                <div key={w}>{w}</div>
                            ))}
                        </div>
                        <div className="grid grid-cols-7 gap-1">
                            {cells.map(({ date, state, bill }) => {
                                const selected = selectedDate ? isSameDay(date, selectedDate) : false;
                                return (
                                    <BillScheduleCalendarDay
                                        key={date.toISOString()}
                                        day={date}
                                        state={state}
                                        selected={selected}
                                        bill={bill}
                                        onSelect={(d) => onSelectDate(d, bill)}
                                    />
                                );
                            })}
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default BillScheduleCalendar;
