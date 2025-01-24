import { usePage } from "@inertiajs/react";
import { DateCalendar } from "@mui/x-date-pickers";
import BillScheduleCalendarDay from "app/frontend/components/bill/creator/scheduler/BillScheduleCalendarDay";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { parseISO } from "date-fns";
import { useMemo, useState } from "react";
import { sway } from "sway";

const BillScheduleCalendar: React.FC<IBillScheduleCalendarProps> = ({
    selectedBill,
    selectedDate,
    setSelectedDate,
    handleSelectBill,
}) => {
    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);

    const now = new Date();
    const [month, setMonth] = useState<number>(now.getMonth());
    const [year, setYear] = useState<number>(now.getFullYear());

    const highlightedDays = useMemo(
        () =>
            bills
                .filter(({ scheduledReleaseDateUtc }) => {
                    if (!scheduledReleaseDateUtc) {
                        return false;
                    }

                    const release = parseISO(scheduledReleaseDateUtc);
                    return release.getMonth() === month && release.getFullYear() === year;
                })
                .map(({ scheduledReleaseDateUtc }) => parseISO(scheduledReleaseDateUtc).getDate()),
        [bills, month, year],
    );

    return (
        <DateCalendar
            onMonthChange={(newMonth) => setMonth(newMonth.getMonth())}
            onYearChange={(newYear) => setYear(newYear.getFullYear())}
            value={selectedDate}
            onChange={(newValue: Date) => {
                setSelectedDate(newValue);
                if (newValue) {
                    const d = new Date(newValue);
                    const b = bills.find(({ scheduledReleaseDateUtc }) => {
                        if (!scheduledReleaseDateUtc) {
                            return false;
                        }

                        const release = parseISO(scheduledReleaseDateUtc);
                        return (
                            release.getMonth() === d.getMonth() &&
                            release.getFullYear() === d.getFullYear() &&
                            release.getDate() === d.getDate()
                        );
                    });
                    if (
                        b &&
                        (bill?.id !== b.id || ((selectedBill.value as number) > 0 && bill?.scheduledReleaseDateUtc))
                    ) {
                        handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: newValue.toISOString() });
                    }
                }
            }}
            slots={{
                day: (props) => (
                    <BillScheduleCalendarDay
                        {...props}
                        bill={bills.find((b) => {
                            if (b.scheduledReleaseDateUtc) {
                                const d = parseISO(b.scheduledReleaseDateUtc);
                                return (
                                    d.getDate() === props.day.getDate() && d.getFullYear() === props.day.getFullYear()
                                );
                            }
                        })}
                    />
                ),
            }}
            slotProps={{
                day: {
                    highlightedDays,
                } as any,
            }}
        />
    );
};

export default BillScheduleCalendar;
