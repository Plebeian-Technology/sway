import { usePage } from "@inertiajs/react";
import { DateCalendar } from "@mui/x-date-pickers";
import BillScheduleCalendarDay from "app/frontend/components/bill/creator/scheduler/BillScheduleCalendarDay";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import dayjs from "dayjs";
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

    const now = dayjs();
    const [month, setMonth] = useState<number>(now.month());
    const [year, setYear] = useState<number>(now.year());

    const highlightedDays = useMemo(
        () =>
            bills
                .filter(({ scheduledReleaseDateUtc }) => {
                    const release = dayjs(scheduledReleaseDateUtc);
                    return release.month() === month && release.year() === year;
                })
                .map(({ scheduledReleaseDateUtc }) => dayjs(scheduledReleaseDateUtc).date()),
        [bills, month, year],
    );

    return (
        <DateCalendar
            onMonthChange={(newMonth) => setMonth(newMonth.month())}
            onYearChange={(newYear) => setYear(newYear.year())}
            value={selectedDate}
            onChange={(newValue) => {
                setSelectedDate(newValue);
                if (newValue) {
                    const d = dayjs(newValue);
                    const b = bills.find(({ scheduledReleaseDateUtc }) => {
                        const release = dayjs(scheduledReleaseDateUtc);
                        return (
                            release.month() === d.month() && release.year() === d.year() && release.date() === d.date()
                        );
                    });
                    if (b && bill?.id !== b.id) {
                        handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: newValue.toISOString() });
                    } else if (b && (selectedBill.value as number) > 0 && bill?.scheduledReleaseDateUtc) {
                        handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: newValue.toISOString() });
                    }
                }
            }}
            slots={{
                day: BillScheduleCalendarDay,
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
