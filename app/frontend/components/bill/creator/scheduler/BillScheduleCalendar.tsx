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
                .filter(({ scheduled_release_date_utc }) => {
                    if (!scheduled_release_date_utc) {
                        return false;
                    }

                    const release = parseISO(scheduled_release_date_utc);
                    return release.getMonth() === month && release.getFullYear() === year;
                })
                .map(({ scheduled_release_date_utc }) => parseISO(scheduled_release_date_utc).getDate()),
        [bills, month, year],
    );

    return (
        <DateCalendar
            onMonthChange={(newMonth) => setMonth(newMonth.getMonth())}
            onYearChange={(newYear) => setYear(newYear.getFullYear())}
            value={selectedDate}
            onChange={(newValue: Date | null) => {
                setSelectedDate(newValue);
                if (newValue) {
                    const d = new Date(newValue);
                    const b = bills.find(({ scheduled_release_date_utc }) => {
                        if (!scheduled_release_date_utc) {
                            return false;
                        }

                        const release = parseISO(scheduled_release_date_utc);
                        return (
                            release.getMonth() === d.getMonth() &&
                            release.getFullYear() === d.getFullYear() &&
                            release.getDate() === d.getDate()
                        );
                    });
                    if (
                        b &&
                        (bill?.id !== b.id || ((selectedBill.value as number) > 0 && bill?.scheduled_release_date_utc))
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
                            if (b.scheduled_release_date_utc) {
                                const d = parseISO(b.scheduled_release_date_utc);
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
