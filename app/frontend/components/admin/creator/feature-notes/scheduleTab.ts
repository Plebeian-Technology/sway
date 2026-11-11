import { TFeatureNoteGroup } from "app/frontend/components/admin/creator/feature-notes/types";

export const SCHEDULE_TAB_NOTES = {
    "schedule.calendar": {
        feature: "the month calendar",
        note: "Only one bill can be the Bill of the Month on a given day, so this shows which days are already taken.",
    },
    "schedule.selectedBill": {
        feature: "the selected bill panel",
        note: "The calendar shows days and the list shows bills, so this says which bill your next click will schedule.",
    },
    "schedule.currentRelease": {
        feature: "the current release day",
        note: "This is the day already saved for this bill, not the day you are pointing at.",
    },
    "schedule.selectedDate": {
        feature: "the selected date",
        note: "This is the day you clicked, and it is not booked until you press Schedule bill.",
    },
    "schedule.scheduleBill": {
        feature: "the Schedule bill button",
        note: "This books the bill as the Bill of the Month that readers see on that day.",
    },
    "schedule.removeFromSchedule": {
        feature: "the Remove from schedule button",
        note: "A day holds only one bill, so moving a bill means freeing its day here and adding it again.",
    },
    "schedule.upcoming": {
        feature: "the upcoming scheduled list",
        note: "The calendar shows one month at a time, so this is how you see every release day booked ahead.",
    },
    "schedule.past": {
        feature: "the past scheduled list",
        note: "Released bills sit in past months, so this saves paging the calendar back to find them.",
    },
    "schedule.unscheduled": {
        feature: "the unscheduled list",
        note: "A whole session of bills would bury the rest of the page, so this list starts closed and stays as you leave it.",
    },
} as const satisfies TFeatureNoteGroup;
