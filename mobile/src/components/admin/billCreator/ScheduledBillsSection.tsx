// @lat: [[mobile-bill-creator#Sections#The schedule section]]
import React, { useMemo, useState } from "react";
import { Pressable as RNPressable, Text, View } from "react-native";

import { calendarDayToDate, localToday } from "../../../utils/calendarDay";
import { Pressable } from "../../ui/Pressable";
import type { SchedulePickerBill } from "./BillScheduleSection";

interface ScheduledBillsSectionProps {
    bills: SchedulePickerBill[];
    selectedBillId: number | null;
    onSelectBill: (bill: SchedulePickerBill) => void;
}

const PAGE_SIZE = 5;

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const bodyText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";

const monthKey = (day: string) => day.slice(0, 7);
const monthLabel = (day: string) =>
    calendarDayToDate(day).toLocaleDateString("en-US", { month: "long", year: "numeric" });
const dayLabel = (day: string) =>
    calendarDayToDate(day).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });

interface RowProps {
    bill: SchedulePickerBill;
    selected: boolean;
    onSelectBill: (bill: SchedulePickerBill) => void;
}

function BillRow({ bill, selected, onSelectBill }: RowProps) {
    return (
        <RNPressable
            testID={`admin-schedule-row-${bill.id}`}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={`${bill.external_id}${selected ? ", selected" : ""}`}
            onPress={() => {
                if (!selected) onSelectBill(bill);
            }}
            className="flex-row items-center justify-between py-2 border-b border-border-soft-light dark:border-border-soft-dark"
        >
            <View className="flex-1 pr-3">
                <Text className={bodyText}>{bill.external_id}</Text>
                <Text numberOfLines={2} className={mutedText}>
                    {bill.title || "Untitled bill"}
                </Text>
                {bill.scheduled_release_date_utc ? (
                    <Text className={mutedText}>{dayLabel(bill.scheduled_release_date_utc)}</Text>
                ) : null}
            </View>
            {selected ? <Text className={bodyText}>Selected</Text> : null}
        </RNPressable>
    );
}

interface PagedBillsProps extends Omit<RowProps, "bill" | "selected"> {
    bills: SchedulePickerBill[];
    selectedBillId: number | null;
    moreTestID: string;
}

function PagedBills({ bills, selectedBillId, onSelectBill, moreTestID }: PagedBillsProps) {
    const [shown, setShown] = useState(PAGE_SIZE);
    return (
        <>
            {bills.slice(0, shown).map((bill) => (
                <BillRow key={bill.id} bill={bill} selected={bill.id === selectedBillId} onSelectBill={onSelectBill} />
            ))}
            {shown < bills.length ? (
                <Pressable
                    testID={moreTestID}
                    variant="ghost"
                    accessibilityLabel="Show more bills"
                    onPress={() => setShown(shown + PAGE_SIZE)}
                >
                    <Text className={bodyText}>Show more</Text>
                </Pressable>
            ) : null}
        </>
    );
}

export default function ScheduledBillsSection({ bills, selectedBillId, onSelectBill }: ScheduledBillsSectionProps) {
    const [unscheduledOpen, setUnscheduledOpen] = useState(false);

    const { upcoming, past, unscheduled } = useMemo(() => {
        const today = localToday();
        const groups = {
            upcoming: [] as SchedulePickerBill[],
            past: [] as SchedulePickerBill[],
            unscheduled: [] as SchedulePickerBill[],
        };
        for (const bill of bills) {
            const day = bill.scheduled_release_date_utc;
            if (!day) groups.unscheduled.push(bill);
            else if (calendarDayToDate(day) >= today) groups.upcoming.push(bill);
            else groups.past.push(bill);
        }
        const byDay = (a: SchedulePickerBill, b: SchedulePickerBill) =>
            (a.scheduled_release_date_utc ?? "").localeCompare(b.scheduled_release_date_utc ?? "");
        groups.upcoming.sort(byDay);
        groups.past.sort((a, b) => byDay(b, a));
        return groups;
    }, [bills]);

    const months: SchedulePickerBill[][] = [];
    for (const bill of upcoming) {
        const last = months[months.length - 1];
        if (
            last &&
            monthKey(last[0].scheduled_release_date_utc as string) ===
                monthKey(bill.scheduled_release_date_utc as string)
        ) {
            last.push(bill);
        } else {
            months.push([bill]);
        }
    }

    return (
        <View testID="admin-schedule-lists" className="px-4 mt-6">
            <Text className={`mb-2 ${bodyText}`}>Upcoming scheduled ({upcoming.length})</Text>
            {months.length === 0 ? (
                <Text className={`italic ${mutedText}`}>No scheduled bills. Pick a future day for this bill.</Text>
            ) : (
                months.map((monthBills) => {
                    const first = monthBills[0].scheduled_release_date_utc as string;
                    return (
                        <View key={monthKey(first)} className="mb-2">
                            <Text
                                testID={`admin-schedule-month-${monthKey(first)}`}
                                className={`mt-2 uppercase ${mutedText}`}
                            >
                                {monthLabel(first)}
                            </Text>
                            {monthBills.map((bill) => (
                                <BillRow
                                    key={bill.id}
                                    bill={bill}
                                    selected={bill.id === selectedBillId}
                                    onSelectBill={onSelectBill}
                                />
                            ))}
                        </View>
                    );
                })
            )}

            {past.length > 0 ? (
                <View className="mt-4">
                    <Text className={`mb-2 ${bodyText}`}>Past scheduled ({past.length})</Text>
                    <PagedBills
                        bills={past}
                        selectedBillId={selectedBillId}
                        onSelectBill={onSelectBill}
                        moreTestID="admin-schedule-past-more"
                    />
                </View>
            ) : null}

            <View className="mt-4">
                <Pressable
                    testID="admin-schedule-unscheduled-toggle"
                    variant="ghost"
                    accessibilityLabel="Show or hide the unscheduled bills"
                    accessibilityState={{ expanded: unscheduledOpen }}
                    onPress={() => setUnscheduledOpen(!unscheduledOpen)}
                >
                    <Text className={bodyText}>Unscheduled ({unscheduled.length})</Text>
                </Pressable>
                {unscheduledOpen ? (
                    unscheduled.length === 0 ? (
                        <Text className={`italic ${mutedText}`}>
                            No unscheduled bills. Everything is on the calendar.
                        </Text>
                    ) : (
                        <PagedBills
                            bills={unscheduled}
                            selectedBillId={selectedBillId}
                            onSelectBill={onSelectBill}
                            moreTestID="admin-schedule-unscheduled-more"
                        />
                    )
                ) : null}
            </View>
        </View>
    );
}
