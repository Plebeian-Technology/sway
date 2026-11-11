import { router, usePage } from "@inertiajs/react";
import { useCallback, useReducer } from "react";
import { sway } from "sway";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { ROUTES } from "app/frontend/sway_constants";
import { notify } from "app/frontend/sway_utils";
import { calendarDayToDate, dateToCalendarDay, isValidDate } from "app/frontend/sway_utils/datetimes";
import BillScheduleCalendar from "app/frontend/components/admin/creator/BillScheduleCalendar";
import BillScheduleSidebar from "app/frontend/components/admin/creator/BillScheduleSidebar";
import BillScheduleSelectedBill from "app/frontend/components/admin/creator/bill-schedule/BillScheduleSelectedBill";

interface IPageProps {
    bill?: sway.IBill;
    bills: sway.IBillPickerOption[];
    [key: string]: unknown;
}

// @lat: [[bill-schedule-calendar-dates#Bare release dates in the bill schedule tab]]
const BillSchedule: React.FC = () => {
    const page = usePage<IPageProps>();
    const bill = page.props.bill;

    const params = useSearchParams();

    // @lat: [[bill-schedule-calendar-dates#Why picking a day reaches no server]]
    const [, dateDidChange] = useReducer((count: number) => count + 1, 0);

    const scheduledUtc = bill?.scheduled_release_date_utc ?? null;
    // @lat: [[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]
    const qsDate = params.get(BILL_SCHEDULER_PARAMS_KEY);
    const parsedQs = qsDate ? calendarDayToDate(qsDate) : null;
    const validQs = parsedQs && isValidDate(parsedQs) && dateToCalendarDay(parsedQs) === qsDate ? parsedQs : null;
    const selectedDate: Date | null = validQs ?? (scheduledUtc ? calendarDayToDate(scheduledUtc) : null);

    const handleSelectBill = useCallback(
        (b: sway.IBillPickerOption, newParams?: Record<string, string>) => {
            const qs = { ...params.entries, ...(newParams ?? {}) };
            if (b.id && b.id > 0) {
                // @lat: [[bill-schedule-calendar-dates#Why switching bills preserves the schedule tab and carries the clicked date]]
                router.get(ROUTES.billCreatorTab(b.id, "schedule"), qs, {
                    preserveState: true,
                    preserveScroll: true,
                    replace: true,
                });
            } else {
                router.get(ROUTES.billCreator, qs, {
                    preserveState: true,
                    preserveScroll: true,
                    replace: true,
                });
            }
        },
        [params.entries],
    );

    const handleCalendarSelect = useCallback(
        (d: Date, existingBill: sway.IBillPickerOption | undefined) => {
            // @lat: [[bill-schedule-calendar-dates#Why switching bills preserves the schedule tab and carries the clicked date]]
            if (existingBill && bill?.id !== existingBill.id) {
                handleSelectBill(existingBill, { [BILL_SCHEDULER_PARAMS_KEY]: dateToCalendarDay(d) });
                return;
            }
            if (typeof window === "undefined") return;

            const url = new URL(window.location.href);
            url.searchParams.set(BILL_SCHEDULER_PARAMS_KEY, dateToCalendarDay(d));
            window.history.replaceState(window.history.state, "", url.pathname + url.search);
            dateDidChange();
        },
        [bill?.id, handleSelectBill],
    );

    const billId = bill?.id;
    const submitSchedule = useCallback(
        (scheduleDate: Date | null) => {
            if (!billId || billId <= 0) {
                notify({
                    level: "error",
                    title: "Save new Bill of the Month before scheduling release date.",
                });
                return;
            }
            router.put(
                "/bill_of_the_month_schedule/0",
                {
                    scheduled_release_date_utc: scheduleDate ? dateToCalendarDay(scheduleDate) : null,
                    bill_id: billId,
                    bill_creator_tab: ETab.Schedule,
                },
                {
                    preserveScroll: true,
                    onError: (errors) => {
                        console.error("BillSchedule: schedule update failed", errors);
                    },
                },
            );
        },
        [billId],
    );

    const selectedBillId = bill?.id ?? null;

    return (
        <div className="grid min-w-0 max-w-full grid-cols-1 gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
            <div className="flex flex-col gap-6">
                <BillScheduleCalendar
                    selectedBillId={selectedBillId}
                    selectedDate={selectedDate}
                    onSelectDate={handleCalendarSelect}
                />

                <BillScheduleSelectedBill bill={bill} selectedDate={selectedDate} onSubmitSchedule={submitSchedule} />
            </div>

            <BillScheduleSidebar
                selectedBillId={selectedBillId}
                onSelectBill={(b) => handleSelectBill(b, { [BILL_SCHEDULER_PARAMS_KEY]: "" })}
            />
        </div>
    );
};

export default BillSchedule;
