import { useForm, usePage } from "@inertiajs/react";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { IBillScheduleCalendarProps } from "app/frontend/components/bill/creator/scheduler/types";
import { notify } from "app/frontend/sway_utils";
import { format } from "date-fns";
import { useCallback, useEffect, useMemo } from "react";
import { Button, Form } from "react-bootstrap";
import { sway } from "sway";

const BillScheduleCalendarSelectedBill: React.FC<Omit<IBillScheduleCalendarProps, "setSelectedDate">> = ({
    selectedBill,
    selectedDate,
}) => {
    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);

    const {
        data,
        setData,
        put,
        processing,
        errors: _errors,
    } = useForm<{ scheduled_release_date_utc: string | null; bill_id: number; tab_key: ETab }>({
        scheduled_release_date_utc: (selectedDate || new Date()).toLocaleDateString("en-US"),
        bill_id: selectedBill.value as number,
        tab_key: ETab.Schedule,
    });

    const isBillReleaseable = !bill?.scheduledReleaseDateUtc;

    const onSubmit = useCallback(() => {
        if (!bill?.id) {
            notify({
                level: "error",
                title: "Save new Bill of the Week before scheduling release date.",
            });
        } else {
            put("/bill_of_the_week_schedule/0");
        }
    }, [bill?.id, put]);

    useEffect(() => {
        setData("scheduled_release_date_utc", selectedDate?.toLocaleDateString?.("en-US") || null);
    }, [selectedDate, setData]);

    return (
        <Form onSubmit={onSubmit}>
            <div>
                <span className="bold">Bill: </span>
                {bill?.externalId} - {bill?.title || "New Bill of the Week"}
            </div>
            {bill?.id && data.scheduled_release_date_utc && (
                <div className="my-3">
                    <span className="bold">Current Release Date: </span>
                    {format(new Date(data.scheduled_release_date_utc), "MMMM dd, yyyy")}
                </div>
            )}
            <div className="my-3">
                <span className="bold">Selected Date: </span>
                {selectedDate && format(selectedDate, "MMMM dd, yyyy")}
            </div>
            <div className="row my-3">
                {isBillReleaseable ? (
                    <div className="col">
                        <Button disabled={processing} variant="outline-primary" type="submit" className="w-100">
                            Schedule Bill
                        </Button>
                    </div>
                ) : (
                    <div className="col">
                        <Button
                            disabled={processing}
                            variant="outline-primary"
                            onClick={() => setData("scheduled_release_date_utc", null)}
                            className="w-100"
                        >
                            Remove Bill from Schedule
                        </Button>
                    </div>
                )}
            </div>
            <div className="row my-3">
                <div className="col">* To re-schedule a bill, remove it from the schedule and add it again.</div>
            </div>
        </Form>
    );
};

export default BillScheduleCalendarSelectedBill;
