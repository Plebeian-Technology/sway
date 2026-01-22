import { usePage } from "@inertiajs/react";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { useMemo } from "react";
import { sway } from "sway";

const BillScheduleCalendar: React.FC<IBillScheduleCalendarProps> = ({
    selectedBill,
    selectedDate,
    setSelectedDate,
    handleSelectBill,
}) => {
    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);

    const onChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const val = e.target.value;
        if (!val) {
            setSelectedDate(null);
            return;
        }

        const d = new Date(val);
        setSelectedDate(d);

        const b = bills.find(({ scheduled_release_date_utc }) => {
            if (!scheduled_release_date_utc) {
                return false;
            }
            // scheduled_release_date_utc is ISO string.
            // Check if same day (UTC)
            return new Date(scheduled_release_date_utc).toISOString().split("T")[0] === val;
        });

        if (
            b &&
            (bill?.id !== b.id || ((selectedBill.value as number) > 0 && bill?.scheduled_release_date_utc))
        ) {
            handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: d.toISOString() });
        }
    };

    const dateString = selectedDate ? selectedDate.toISOString().split("T")[0] : "";

    return (
        <div className="p-3 border rounded">
            <label className="form-label bold">Select Date</label>
            <input type="date" className="form-control" value={dateString} onChange={onChange} />
        </div>
    );
};

export default BillScheduleCalendar;
