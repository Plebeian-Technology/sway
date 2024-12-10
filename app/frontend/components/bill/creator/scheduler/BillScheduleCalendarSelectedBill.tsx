import { router, usePage } from "@inertiajs/react";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { notify } from "app/frontend/sway_utils";
import { format, parseISO } from "date-fns";
import { useCallback, useMemo } from "react";
import { Button } from "react-bootstrap";
import { sway } from "sway";

const BillScheduleCalendarSelectedBill: React.FC<Omit<IBillScheduleCalendarProps, "setSelectedDate">> = ({
    selectedBill,
    selectedDate,
}) => {
    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);

    const isBillReleaseable = !bill?.scheduledReleaseDateUtc;

    const handleScheduleBill = useCallback(
        (newReleaseDate: Date | null) => {
            if (!bill?.id) {
                notify({
                    level: "error",
                    title: "Save new Bill of the Week before scheduling release date.",
                });
            } else {
                router.put("/bill_of_the_week_schedule/0", {
                    scheduled_release_date_utc: newReleaseDate?.toLocaleDateString("en-US") || null,
                    bill_id: bill.id,
                    tab_key: ETab.Schedule,
                });
            }
        },
        [bill?.id],
    );

    return (
        <>
            <div>
                <span className="bold">Bill: </span>
                {bill?.externalId} - {bill?.title || "New Bill of the Week"}
            </div>
            {bill?.id && bill.scheduledReleaseDateUtc && (
                <div className="my-3">
                    <span className="bold">Current Release Date: </span>
                    {format(parseISO(bill.scheduledReleaseDateUtc), "MMMM dd, yyyy")}
                </div>
            )}
            <div className="my-3">
                <span className="bold">Selected Date: </span>
                {selectedDate && format(selectedDate, "MMMM dd, yyyy")}
            </div>
            <div className="row my-3">
                {isBillReleaseable ? (
                    <div className="col">
                        <Button
                            variant="outline-primary"
                            onClick={() => handleScheduleBill(selectedDate)}
                            className="w-100"
                        >
                            Schedule Bill
                        </Button>
                    </div>
                ) : (
                    <div className="col">
                        <Button variant="outline-primary" onClick={() => handleScheduleBill(null)} className="w-100">
                            Remove Bill from Schedule
                        </Button>
                    </div>
                )}
            </div>
            <div className="row my-3">
                <div className="col">* To re-schedule a bill, remove it from the schedule and add it again.</div>
            </div>
        </>
    );
};

export default BillScheduleCalendarSelectedBill;
