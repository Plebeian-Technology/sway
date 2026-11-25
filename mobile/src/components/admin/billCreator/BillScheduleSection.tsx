// @lat: [[mobile-bill-creator#Sections#The schedule section]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import { calendarDayToDate, localToday, parseCalendarDay } from "../../../utils/calendarDay";
import { shortBillTitle } from "../../../utils/billTitle";
import { FormField } from "../../ui/FormField";
import { Pressable } from "../../ui/Pressable";

export interface SchedulePickerBill {
    id: number;
    external_id: string | null;
    title: string | null;
    scheduled_release_date_utc: string | null;
}

export interface ScheduleBill {
    id?: number | null;
    external_id?: string | null;
    title?: string | null;
    scheduled_release_date_utc?: string | null;
}

interface BillScheduleSectionProps {
    billId: number | null;
    bill: ScheduleBill | undefined;
    bills: SchedulePickerBill[];
    onChanged: () => void;
}

const NEW_BILL_MESSAGE = "Save new Bill of the Month before scheduling release date.";
const RESCHEDULE_NOTE = "To re-schedule a bill, remove it from the schedule and add it again.";

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const errorText = "mb-3 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";
const bodyText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";

const formatDay = (day: string) =>
    calendarDayToDate(day).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" });

export default function BillScheduleSection({ billId, bill, bills, onChanged }: BillScheduleSectionProps) {
    const scheduledDay = bill?.scheduled_release_date_utc ?? null;
    const [dayText, setDayText] = useState(scheduledDay ?? "");
    const { run, loading, errorMessage } = useAdminMutation<unknown>(
        "patch",
        Routes.adminBillOfTheMonthSchedule(billId ?? 0),
    );

    const heading = <Text className={`mb-2 ${bodyText}`}>Selected bill</Text>;

    if (billId === null) {
        return (
            <View testID="admin-schedule-selected" className="px-4 mt-2">
                {heading}
                <Text className="text-sm italic font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {NEW_BILL_MESSAGE}
                </Text>
            </View>
        );
    }

    const typedDate = parseCalendarDay(dayText);
    const holder = typedDate
        ? bills.find((b) => b.id !== billId && b.scheduled_release_date_utc === dayText.trim())
        : undefined;
    const dayProblem =
        dayText.trim() === ""
            ? undefined
            : typedDate === null
              ? "Enter a day as YYYY-MM-DD."
              : typedDate < localToday()
                ? "Pick a day that is not in the past."
                : holder
                  ? `${holder.external_id} is already scheduled for that day.`
                  : undefined;
    const canSchedule = typedDate !== null && dayProblem === undefined;

    const send = async (day: string | null) => {
        const response = await run({ bill_id: billId, scheduled_release_date_utc: day });
        if (response !== undefined) onChanged();
    };

    return (
        <View testID="admin-schedule-selected" className="px-4 mt-2">
            {heading}
            <Text className={`mb-3 ${bodyText}`}>
                {bill?.external_id || "—"}
                {bill?.title ? ` — ${shortBillTitle(bill.title)}` : ""}
            </Text>
            {scheduledDay ? (
                <>
                    <Text testID="admin-schedule-current" className={`mb-3 ${bodyText}`}>
                        Scheduled for {formatDay(scheduledDay)}
                    </Text>
                    {errorMessage ? (
                        <Text testID="admin-schedule-error" className={errorText}>
                            {errorMessage}
                        </Text>
                    ) : null}
                    <Pressable
                        testID="admin-schedule-remove"
                        variant="outline"
                        disabled={loading}
                        accessibilityLabel="Remove the bill from the schedule"
                        onPress={() => void send(null)}
                    >
                        <Text className={bodyText}>{loading ? "Removing..." : "Remove from schedule"}</Text>
                    </Pressable>
                    <Text className={`mt-3 italic ${mutedText}`}>{RESCHEDULE_NOTE}</Text>
                </>
            ) : (
                <>
                    <Text className={`mb-3 ${mutedText}`}>Unscheduled</Text>
                    <FormField
                        testID="admin-schedule-date"
                        label="Release day"
                        value={dayText}
                        onChangeText={setDayText}
                        placeholder="YYYY-MM-DD"
                        error={dayProblem}
                        disabled={loading}
                        keyboardType="numbers-and-punctuation"
                    />
                    {errorMessage ? (
                        <Text testID="admin-schedule-error" className={errorText}>
                            {errorMessage}
                        </Text>
                    ) : null}
                    <Pressable
                        testID="admin-schedule-save"
                        variant="default"
                        disabled={loading || !canSchedule}
                        accessibilityLabel="Schedule the bill for the chosen day"
                        onPress={() => void send(dayText.trim())}
                    >
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            {loading ? "Scheduling..." : "Schedule bill"}
                        </Text>
                    </Pressable>
                </>
            )}
        </View>
    );
}
