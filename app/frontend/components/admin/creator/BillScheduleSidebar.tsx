import { usePage } from "@inertiajs/react";
import { useMemo } from "react";
import { sway } from "sway";
import { Badge } from "app/frontend/components/ui/badge";
import CollapsiblePanel from "app/frontend/components/CollapsiblePanel";
import Pagination from "app/frontend/components/Pagination";
import { usePagination } from "app/frontend/hooks/usePagination";
import { calendarDayToDate } from "app/frontend/sway_utils/datetimes";
import BillScheduleSidebarRow from "app/frontend/components/admin/creator/bill-schedule/BillScheduleSidebarRow";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { useTime } from "app/frontend/hooks/useTime";

const UNSCHEDULED_PAGE_SIZE = 5;
const PAST_PAGE_SIZE = 5;

interface IProps {
    selectedBillId: number | null;
    onSelectBill: (bill: sway.IBillPickerOption) => void;
}

interface IPageProps {
    bills: sway.IBillPickerOption[];
    [key: string]: unknown;
}

// @lat: [[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]
const BillScheduleSidebar: React.FC<IProps> = ({ selectedBillId, onSelectBill }) => {
    const bills = usePage<IPageProps>().props.bills;

    const now = useTime();

    const scheduled = useMemo(() => {
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        return bills.reduce(
            (sum, b) => {
                if (!b.scheduled_release_date_utc) return sum;
                const d = calendarDayToDate(b.scheduled_release_date_utc);
                if (d >= today) {
                    sum.upcoming.push(b);
                } else {
                    sum.past.push(b);
                }
                return sum;
            },
            { upcoming: [] as sway.IBillPickerOption[], past: [] as sway.IBillPickerOption[] },
        );
    }, [now, bills]);

    const pastPage = usePagination(scheduled.past, PAST_PAGE_SIZE);
    const unscheduled = useMemo(() => bills.filter((b) => !b.scheduled_release_date_utc), [bills]);
    const unscheduledPage = usePagination(unscheduled, UNSCHEDULED_PAGE_SIZE);

    return (
        <div className="flex flex-col gap-6">
            <section className="rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
                <div className="flex items-center justify-between pb-2">
                    <div className="flex items-center gap-1.5">
                        <h3 className="text-xs font-semibold uppercase tracking-widest">Upcoming scheduled</h3>
                        <FeatureInfo note="schedule.upcoming" />
                    </div>
                    <Badge variant="stamp" tone="primary">
                        <span className="tabular-nums lining-nums">{scheduled.upcoming.length}</span>
                    </Badge>
                </div>
                <div className="border-b-neo border-border-soft" />
                {scheduled.upcoming.length === 0 ? (
                    <p className="pt-3 text-sm italic text-muted-foreground">
                        No scheduled bills — pick a future date on the calendar.
                    </p>
                ) : (
                    <ul className="flex flex-col">
                        {scheduled.upcoming.map((b) => (
                            <BillScheduleSidebarRow
                                key={`upcoming-${b.id}`}
                                bill={b}
                                selectedBillId={selectedBillId}
                                date={b.scheduled_release_date_utc as string}
                                onSelectBill={onSelectBill}
                            />
                        ))}
                    </ul>
                )}
            </section>

            {!!scheduled.past.length && (
                <section className="rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
                    <div className="flex items-center justify-between pb-2">
                        <div className="flex items-center gap-1.5">
                            <h3 className="text-xs font-semibold uppercase tracking-widest">Past scheduled</h3>
                            <FeatureInfo note="schedule.past" />
                        </div>
                        <Badge variant="stamp" tone="primary">
                            <span className="tabular-nums lining-nums">{scheduled.past.length}</span>
                        </Badge>
                    </div>
                    <div className="border-b-neo border-border-soft" />

                    <ul className="flex flex-col">
                        {pastPage.pageItems.map((b) => (
                            <BillScheduleSidebarRow
                                key={`past-${b.id}`}
                                bill={b}
                                selectedBillId={selectedBillId}
                                date={b.scheduled_release_date_utc as string}
                                onSelectBill={onSelectBill}
                            />
                        ))}
                    </ul>
                    <Pagination
                        page={pastPage.page}
                        pageCount={pastPage.pageCount}
                        onPageChange={pastPage.goToPage}
                        className="justify-center pt-3"
                    />
                </section>
            )}

            <section className="rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
                <div className="flex items-start gap-1.5">
                    <div className="min-w-0 flex-1">
                        <CollapsiblePanel
                            storageKey="sway:bill-schedule:accordion:unscheduled"
                            defaultOpen={false}
                            title={
                                <span className="flex flex-1 items-center justify-between">
                                    <span className="text-xs font-semibold uppercase tracking-widest">Unscheduled</span>
                                    <Badge variant="stamp" tone="neutral">
                                        <span className="tabular-nums lining-nums">{unscheduled.length}</span>
                                    </Badge>
                                </span>
                            }
                        >
                            {unscheduled.length === 0 ? (
                                <p className="text-sm italic text-muted-foreground">
                                    No unscheduled bills — everything is on the calendar.
                                </p>
                            ) : (
                                <>
                                    <ul className="flex flex-col">
                                        {unscheduledPage.pageItems.map((b) => (
                                            <BillScheduleSidebarRow
                                                key={`unscheduled-${b.id}`}
                                                bill={b}
                                                selectedBillId={selectedBillId}
                                                onSelectBill={onSelectBill}
                                            />
                                        ))}
                                    </ul>
                                    <Pagination
                                        page={unscheduledPage.page}
                                        pageCount={unscheduledPage.pageCount}
                                        onPageChange={unscheduledPage.goToPage}
                                        className="justify-center pt-3"
                                    />
                                </>
                            )}
                        </CollapsiblePanel>
                    </div>
                    <div className="shrink-0 py-4 text-sm">
                        <FeatureInfo note="schedule.unscheduled" />
                    </div>
                </div>
            </section>
        </div>
    );
};

export default BillScheduleSidebar;
