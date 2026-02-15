import { usePage } from "@inertiajs/react";
import BillScheduleCalendarDay from "app/frontend/components/bill/creator/scheduler/BillScheduleCalendarDay";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { useMemo, useState } from "react";
import { Button } from "react-bootstrap";
import { FiChevronLeft, FiChevronRight } from "react-icons/fi";
import { sway } from "sway";

const getDaysInMonth = (month: number, year: number) => {
    return new Date(year, month + 1, 0).getDate();
};

const getFirstDayOfMonth = (month: number, year: number) => {
    return new Date(year, month, 1).getDay();
};

const BillScheduleCalendar: React.FC<IBillScheduleCalendarProps> = ({
    selectedBill,
    selectedDate,
    setSelectedDate,
    handleSelectBill,
}) => {
    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);

    const now = new Date();
    const [month, setMonth] = useState<number>(selectedDate ? selectedDate.getMonth() : now.getMonth());
    const [year, setYear] = useState<number>(selectedDate ? selectedDate.getFullYear() : now.getFullYear());

    const highlightedDays = useMemo(
        () =>
            bills
                .filter(({ scheduled_release_date_utc }) => {
                    if (!scheduled_release_date_utc) {
                        return false;
                    }

                    const release = new Date(scheduled_release_date_utc);
                    return release.getMonth() === month && release.getFullYear() === year;
                })
                .map(({ scheduled_release_date_utc }) => new Date(scheduled_release_date_utc).getDate()),
        [bills, month, year],
    );

    const onDaySelect = (day: Date) => {
        setSelectedDate(day);
        const b = bills.find(({ scheduled_release_date_utc }) => {
            if (!scheduled_release_date_utc) {
                return false;
            }

            const release = new Date(scheduled_release_date_utc);
            return (
                release.getMonth() === day.getMonth() &&
                release.getFullYear() === day.getFullYear() &&
                release.getDate() === day.getDate()
            );
        });
        if (b && (bill?.id !== b.id || ((selectedBill.value as number) > 0 && bill?.scheduled_release_date_utc))) {
            handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: day.toISOString() });
        }
    };

    const handlePrevMonth = () => {
        if (month === 0) {
            setMonth(11);
            setYear(year - 1);
        } else {
            setMonth(month - 1);
        }
    };

    const handleNextMonth = () => {
        if (month === 11) {
            setMonth(0);
            setYear(year + 1);
        } else {
            setMonth(month + 1);
        }
    };

    const renderCalendar = () => {
        const daysInMonth = getDaysInMonth(month, year);
        const firstDay = getFirstDayOfMonth(month, year);
        const weeks = [];
        let week = [];

        // Previous month days
        const prevMonthDays = getDaysInMonth(month === 0 ? 11 : month - 1, month === 0 ? year - 1 : year);
        for (let i = firstDay - 1; i >= 0; i--) {
            const d = new Date(month === 0 ? year - 1 : year, month === 0 ? 11 : month - 1, prevMonthDays - i);
            week.push(
                <td key={`prev-${d.toISOString()}`} className="p-1">
                    <BillScheduleCalendarDay
                        day={d}
                        bill={undefined}
                        highlightedDays={[]}
                        outsideCurrentMonth
                        onDaySelect={onDaySelect}
                        selected={
                            selectedDate &&
                            selectedDate.getDate() === d.getDate() &&
                            selectedDate.getMonth() === d.getMonth() &&
                            selectedDate.getFullYear() === d.getFullYear()
                        }
                    />
                </td>,
            );
        }

        // Current month days
        for (let i = 1; i <= daysInMonth; i++) {
            const d = new Date(year, month, i);
            const isHighlighted = highlightedDays.includes(i);
            const selected =
                selectedDate &&
                selectedDate.getDate() === i &&
                selectedDate.getMonth() === month &&
                selectedDate.getFullYear() === year;

            const b = isHighlighted
                ? bills.find((_b) => {
                      if (_b.scheduled_release_date_utc) {
                          const date = new Date(_b.scheduled_release_date_utc);
                          return (
                              date.getDate() === i && date.getMonth() === month && date.getFullYear() === year
                          );
                      }
                  })
                : undefined;

            week.push(
                <td key={`curr-${d.toISOString()}`} className="p-1">
                    <BillScheduleCalendarDay
                        day={d}
                        bill={b}
                        highlightedDays={highlightedDays}
                        selected={selected}
                        onDaySelect={onDaySelect}
                    />
                </td>,
            );

            if (week.length === 7) {
                weeks.push(<tr key={`week-${weeks.length}`}>{week}</tr>);
                week = [];
            }
        }

        // Next month days
        let nextMonthDay = 1;
        while (week.length > 0 && week.length < 7) {
            const d = new Date(month === 11 ? year + 1 : year, month === 11 ? 0 : month + 1, nextMonthDay);
            week.push(
                <td key={`next-${d.toISOString()}`} className="p-1">
                    <BillScheduleCalendarDay
                        day={d}
                        bill={undefined}
                        highlightedDays={[]}
                        outsideCurrentMonth
                        onDaySelect={onDaySelect}
                        selected={
                            selectedDate &&
                            selectedDate.getDate() === d.getDate() &&
                            selectedDate.getMonth() === d.getMonth() &&
                            selectedDate.getFullYear() === d.getFullYear()
                        }
                    />
                </td>,
            );
            nextMonthDay++;
        }
        if (week.length > 0) {
            weeks.push(<tr key={`week-${weeks.length}`}>{week}</tr>);
        }

        return weeks;
    };

    const monthName = new Date(year, month).toLocaleString("default", { month: "long" });

    return (
        <div className="card border-0 shadow-sm p-3" style={{ width: "320px" }}>
            <div className="d-flex justify-content-between align-items-center mb-3">
                <Button variant="link" className="p-0 text-dark" onClick={handlePrevMonth}>
                    <FiChevronLeft size={24} />
                </Button>
                <div className="fw-bold fs-5">
                    {monthName} {year}
                </div>
                <Button variant="link" className="p-0 text-dark" onClick={handleNextMonth}>
                    <FiChevronRight size={24} />
                </Button>
            </div>
            <table className="w-100 text-center" style={{ tableLayout: "fixed" }}>
                <thead>
                    <tr>
                        {["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"].map((day) => (
                            <th key={day} className="text-secondary fw-normal pb-2" style={{ fontSize: "0.8rem" }}>
                                {day}
                            </th>
                        ))}
                    </tr>
                </thead>
                <tbody>{renderCalendar()}</tbody>
            </table>
        </div>
    );
};

export default BillScheduleCalendar;
