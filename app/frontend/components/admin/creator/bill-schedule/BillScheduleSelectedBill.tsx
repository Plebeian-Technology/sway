import { sway } from "sway";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { calendarDayToDate, formatDate } from "app/frontend/sway_utils/datetimes";
import { shortBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

interface IProps {
    bill?: sway.IBill;
    selectedDate: Date | null;
    onSubmitSchedule: (scheduleDate: Date | null) => void;
}

const BillScheduleSelectedBill: React.FC<IProps> = ({ bill, selectedDate, onSubmitSchedule }) => {
    const isBillReleaseable = !bill?.scheduled_release_date_utc;

    return (
        <div className="rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
            <div className="flex items-center gap-1.5 pb-2">
                <h3 className="text-xs font-semibold uppercase tracking-widest">Selected bill</h3>
                <FeatureInfo note="schedule.selectedBill" />
            </div>
            <div className="border-b-neo border-border-soft" />
            <dl className="grid grid-cols-1 gap-3 pt-3 text-sm md:grid-cols-2">
                <div>
                    <dt className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">Bill</dt>
                    <dd className="pt-1 font-semibold tabular-nums lining-nums">
                        {bill?.external_id || "—"}
                        {bill?.title ? ` — ${shortBillTitle(bill.title)}` : " — New Bill of the Month"}
                    </dd>
                </div>
                <div>
                    <dt className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                        Current release
                        <FeatureInfo note="schedule.currentRelease" />
                    </dt>
                    <dd className="flex items-center gap-2 pt-1">
                        {bill?.scheduled_release_date_utc ? (
                            <>
                                <span className="tabular-nums lining-nums font-semibold">
                                    {formatDate(calendarDayToDate(bill.scheduled_release_date_utc as string))}
                                </span>
                                <Badge variant="stamp" tone="success">
                                    Scheduled
                                </Badge>
                            </>
                        ) : (
                            <Badge variant="stamp" tone="neutral">
                                Unscheduled
                            </Badge>
                        )}
                    </dd>
                </div>
                <div>
                    <dt className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                        Selected date
                        <FeatureInfo note="schedule.selectedDate" />
                    </dt>
                    <dd className="pt-1 tabular-nums lining-nums">{selectedDate ? formatDate(selectedDate) : "—"}</dd>
                </div>
            </dl>
            <div className="flex flex-col gap-2 pt-4 md:flex-row">
                {isBillReleaseable ? (
                    <div className="flex w-full items-center gap-1.5 sm:w-auto">
                        <Button
                            type="button"
                            variant="default"
                            onClick={() => onSubmitSchedule(selectedDate)}
                            disabled={!selectedDate || !bill?.id}
                            className="min-h-[44px] flex-1 md:flex-none"
                            data-testid="btn-schedule-bill"
                        >
                            Schedule bill
                        </Button>
                        <FeatureInfo note="schedule.scheduleBill" />
                    </div>
                ) : (
                    <div className="flex w-full items-center gap-1.5 sm:w-auto">
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => onSubmitSchedule(null)}
                            className="min-h-[44px] flex-1 md:flex-none"
                            data-testid="btn-remove-bill-schedule"
                        >
                            Remove from schedule
                        </Button>
                        <FeatureInfo note="schedule.removeFromSchedule" />
                    </div>
                )}
            </div>
            <p className="pt-3 text-xs italic text-muted-foreground">
                To re-schedule a bill, remove it from the schedule and add it again.
            </p>
        </div>
    );
};

export default BillScheduleSelectedBill;
