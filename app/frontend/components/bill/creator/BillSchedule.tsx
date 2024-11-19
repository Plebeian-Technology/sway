import { usePage } from "@inertiajs/react";
import BillScheduleCalendar from "app/frontend/components/bill/creator/scheduler/BillScheduleCalendar";
import BillScheduleCalendarSelectedBill from "app/frontend/components/bill/creator/scheduler/BillScheduleCalendarSelectedBill";
import BillSchedulerUnscheduleBillsList from "app/frontend/components/bill/creator/scheduler/BillSchedulerUnscheduleBillsList";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { IBillScheduleProps } from "app/frontend/components/bill/creator/scheduler/types";
import SwayLogo from "app/frontend/components/SwayLogo";
import { IS_MOBILE_PHONE } from "app/frontend/sway_constants";
import { toSelectLabelFromBill } from "app/frontend/sway_utils/bills";
import dayjs, { Dayjs } from "dayjs";
import { useCallback, useMemo, useState } from "react";
import { sway } from "sway";

const BillSchedule: React.FC<IBillScheduleProps> = (props) => {
    const { params, selectedBill, setSelectedBill } = props;

    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);

    const initialValue = useMemo(() => {
        if (bill?.scheduledReleaseDateUtc) {
            return dayjs(bill.scheduledReleaseDateUtc);
        } else if (params.get(BILL_SCHEDULER_PARAMS_KEY)) {
            return dayjs(params.get(BILL_SCHEDULER_PARAMS_KEY));
        } else {
            return null;
        }
    }, [bill?.scheduledReleaseDateUtc, params]);

    const [selectedDate, setSelectedDate] = useState<Dayjs | null>(initialValue);

    const handleSelectBill = useCallback(
        (b: sway.IBill, newParams?: Record<string, string>) => {
            setSelectedBill({ label: toSelectLabelFromBill(b), value: b.id }, { ...params.entries, ...newParams });
        },
        [params.entries, setSelectedBill],
    );

    return (
        <div className="row pt-3">
            <div className="col">
                <div className="row">
                    <div className="col">
                        <BillScheduleCalendar
                            selectedDate={selectedDate}
                            setSelectedDate={setSelectedDate}
                            handleSelectBill={handleSelectBill}
                            {...props}
                        />
                    </div>

                    {IS_MOBILE_PHONE && (
                        <div className="text-center mb-3">
                            <SwayLogo maxWidth={"50px"} />
                        </div>
                    )}

                    <div className="col">
                        <BillScheduleCalendarSelectedBill
                            selectedDate={selectedDate}
                            handleSelectBill={handleSelectBill}
                            {...props}
                        />
                    </div>
                </div>
                <div className="text-center my-5">
                    <SwayLogo maxWidth={"50px"} />
                </div>
                <div className="row">
                    <div className="col">
                        <BillSchedulerUnscheduleBillsList
                            selectedBill={selectedBill}
                            handleSelectBill={handleSelectBill}
                        />
                    </div>
                </div>
            </div>
        </div>
    );
};

export default BillSchedule;
