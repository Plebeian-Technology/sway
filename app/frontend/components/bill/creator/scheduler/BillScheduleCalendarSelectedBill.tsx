import { TZDate } from "@date-fns/tz";
import { router, usePage } from "@inertiajs/react";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { useAxios_NOT_Authenticated_POST_PUT } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/sway_utils";
import { format } from "date-fns";
import { useCallback, useMemo } from "react";
import { Button } from "react-bootstrap";
import { sway } from "sway";

const BillScheduleCalendarSelectedBill: React.FC<Omit<IBillScheduleCalendarProps, "setSelectedDate">> = ({
    selectedBill,
    selectedDate,
}) => {
    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);
    const { post: put } = useAxios_NOT_Authenticated_POST_PUT("/bill_of_the_week_schedule/0", {
        method: "put",
        notifyOnValidationResultFailure: false,
    });

    const isBillReleaseable = !bill?.scheduledReleaseDateUtc;

    const onClick = useCallback(
        (newScheduleDate: Date | null) => {
            if (!bill?.id) {
                notify({
                    level: "error",
                    title: "Save new Bill of the Week before scheduling release date.",
                });
            } else {
                put({
                    scheduled_release_date_utc: newScheduleDate?.toLocaleDateString?.("en-US") || null,
                    bill_id: selectedBill.value as number,
                    tab_key: ETab.Schedule,
                })
                    .then(() => {
                        router.reload();
                    })
                    .catch((e) => {
                        handleError(e);
                        router.reload();
                    });
            }
        },
        [bill?.id, put, selectedBill.value],
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
                    {format(new TZDate(bill.scheduledReleaseDateUtc, "UTC"), "MMMM dd, yyyy")}
                </div>
            )}
            <div className="my-3">
                <span className="bold">Selected Date: </span>
                {selectedDate && format(selectedDate, "MMMM dd, yyyy")}
            </div>
            <div className="row my-3">
                {isBillReleaseable ? (
                    <div className="col">
                        <Button variant="outline-primary" className="w-100" onClick={() => onClick(selectedDate)}>
                            Schedule Bill
                        </Button>
                    </div>
                ) : (
                    <div className="col">
                        <Button variant="outline-primary" onClick={() => onClick(null)} className="w-100">
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
