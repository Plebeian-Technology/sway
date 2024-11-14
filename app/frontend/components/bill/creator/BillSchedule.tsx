import { router, usePage } from "@inertiajs/react";
import { DateCalendar, PickersDay, PickersDayProps } from "@mui/x-date-pickers";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { IParams } from "app/frontend/hooks/useSearchParams";
import { notify } from "app/frontend/sway_utils";
import dayjs, { Dayjs } from "dayjs";
import { useCallback, useMemo, useState } from "react";
import { Button } from "react-bootstrap";
import { ISelectOption, sway } from "sway";

interface IProps {
    params: IParams;
    selectedBill: ISelectOption;
    setSelectedBill: (o: ISelectOption, params?: Record<string, string>) => void;
}
const PARAMS_KEY = "date";

const BillSchedule: React.FC<IProps> = ({ params, selectedBill, setSelectedBill }) => {
    const now = dayjs();
    const [month, setMonth] = useState<number>(now.month());
    const [year, setYear] = useState<number>(now.year());

    const bills = usePage().props.bills as sway.IBill[];
    const bill = useMemo(() => bills.find((b) => b.id === selectedBill.value), [bills, selectedBill.value]);
    const isBillReleaseable = !bill?.scheduledReleaseDateUtc;

    const initialValue = useMemo(() => {
        if (bill?.scheduledReleaseDateUtc) {
            return dayjs(bill.scheduledReleaseDateUtc);
        } else if (params.get(PARAMS_KEY)) {
            return dayjs(params.get(PARAMS_KEY));
        } else {
            return null;
        }
    }, [bill?.scheduledReleaseDateUtc, params]);

    const [value, setValue] = useState<Dayjs | null>(initialValue);

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

    const handleScheduleBill = useCallback(
        (newReleaseDate: Dayjs | null) => {
            if (!bill?.id) {
                notify({
                    level: "error",
                    title: "Save new Bill of the Week before scheduling release date.",
                });
            } else {
                router.put("/bill_of_the_week_schedule/0", {
                    scheduled_release_date_utc: newReleaseDate?.toISOString() || null,
                    bill_id: bill.id,
                    tab_key: ETab.Schedule,
                });
            }
        },
        [bill?.id],
    );

    return (
        <div className="row pt-3">
            <div className="col">
                <DateCalendar
                    onMonthChange={(newMonth) => setMonth(newMonth.month())}
                    onYearChange={(newYear) => setYear(newYear.year())}
                    value={value}
                    onChange={(newValue) => {
                        setValue(newValue);
                        if (newValue) {
                            const d = dayjs(newValue);
                            const b = bills.find(({ scheduledReleaseDateUtc }) => {
                                const release = dayjs(scheduledReleaseDateUtc);
                                return (
                                    release.month() === d.month() &&
                                    release.year() === d.year() &&
                                    release.date() === d.date()
                                );
                            });
                            if (b && bill?.id !== b.id) {
                                setSelectedBill(
                                    { label: `${b.externalId} - ${b.title}`, value: b.id },
                                    { ...params.entries, [PARAMS_KEY]: newValue.toISOString() },
                                );
                            } else if ((selectedBill.value as number) > 0 && bill?.scheduledReleaseDateUtc) {
                                setSelectedBill(
                                    { label: "New Bill", value: -1 },
                                    { ...params.entries, [PARAMS_KEY]: newValue.toISOString() },
                                );
                            }
                        }
                    }}
                    slots={{
                        day: ServerDay,
                    }}
                    slotProps={{
                        day: {
                            highlightedDays,
                        } as any,
                    }}
                />
            </div>
            {value && (
                <div className="col">
                    <div>
                        Bill:{" "}
                        <span className="bold">
                            {bill?.externalId} - {bill?.title || "New Bill of the Week"}
                        </span>
                    </div>
                    <div className="my-3">
                        {bill?.id ? "Schedule bill for release on: " : "Update release date to: "}
                        <span className="bold">{value.format("MMMM DD, YYYY")}</span>
                    </div>
                    <div className="row my-3">
                        {isBillReleaseable ? (
                            <div className="col">
                                <Button
                                    variant="outline-primary"
                                    onClick={() => handleScheduleBill(value)}
                                    className="w-100"
                                >
                                    Schedule Bill
                                </Button>
                            </div>
                        ) : (
                            <div className="col">
                                <Button
                                    variant="outline-primary"
                                    onClick={() => handleScheduleBill(null)}
                                    className="w-100"
                                >
                                    Remove Bill from Schedule
                                </Button>
                            </div>
                        )}
                    </div>
                    <div className="row my-3">
                        * To re-schedule a bill, remove it from the schedule and add it again.
                    </div>
                </div>
            )}
        </div>
    );
};

function ServerDay(props: PickersDayProps<Dayjs> & { highlightedDays?: number[] }) {
    const { highlightedDays = [], day, outsideCurrentMonth, ...other } = props;

    const isSelected = !props.outsideCurrentMonth && highlightedDays.indexOf(props.day.date()) >= 0;

    return (
        <PickersDay
            key={props.day.toString()}
            {...other}
            outsideCurrentMonth={outsideCurrentMonth}
            day={day}
            className={isSelected ? "border border-primary-subtle" : undefined}
            sx={
                isSelected
                    ? {
                          "&:hover": {
                              color: "common.white",
                              backgroundColor: "rgb(60, 110, 247)",
                          },
                      }
                    : undefined
            }
        />
    );
}

export default BillSchedule;
