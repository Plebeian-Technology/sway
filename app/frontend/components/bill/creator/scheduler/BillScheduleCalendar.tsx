import { usePage } from "@inertiajs/react";
import { DateCalendar } from "@mui/x-date-pickers";
import BillScheduleCalendarDay from "app/frontend/components/bill/creator/scheduler/BillScheduleCalendarDay";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { getDate, getMonth, getYear } from "date-fns";
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
    const [month, setMonth] = useState<number>(getMonth(now));
    const [year, setYear] = useState<number>(getYear(now));

    const highlightedDays = useMemo(
        () =>
            bills
                .filter(({ scheduledReleaseDateUtc }) => {
                    if (!scheduledReleaseDateUtc) {
                        return false;
                    }

                    const release = new Date(scheduledReleaseDateUtc);
                    return getMonth(release) === month && getYear(release) === year;
                })
                .map(({ scheduledReleaseDateUtc }) => getDate(scheduledReleaseDateUtc)),
        [bills, month, year],
    );

    return (
        <DateCalendar
            onMonthChange={(newMonth) => setMonth(getMonth(newMonth))}
            onYearChange={(newYear) => setYear(getYear(newYear))}
            value={selectedDate}
            onChange={(newValue) => {
                setSelectedDate(newValue);
                if (newValue) {
                    const d = new Date(newValue);
                    const b = bills.find(({ scheduledReleaseDateUtc }) => {
                        if (!scheduledReleaseDateUtc) {
                            return false;
                        }

                        const release = new Date(scheduledReleaseDateUtc);
                        return (
                            getMonth(release) === getMonth(d) &&
                            getYear(release) === getYear(d) &&
                            getDate(release) === getDate(d)
                        );
                    });
                    if (
                        b &&
                        (bill?.id !== b.id || ((selectedBill.value as number) > 0 && bill?.scheduledReleaseDateUtc))
                    ) {
                        handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: newValue.toLocaleDateString("en-US") });
                    }
                }
            }}
            slots={{
                day: (props) => (
                    <BillScheduleCalendarDay
                        {...props}
                        bill={bills.find((b) => {
                            const d = new Date(b.scheduledReleaseDateUtc);
                            return d.getDate() === props.day.getDate() && d.getFullYear() === props.day.getFullYear();
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
