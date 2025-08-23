import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { KeyOf, sway } from "sway";

type TOmitKeys =
    | "id"
    | "active"
    | "sway_locale_id"
    | "scheduled_release_date_utc"
    | "audio_bucket_path"
    | "audio_by_line";
type TOmittedKeys = KeyOf<Omit<sway.IApiBill, TOmitKeys>>;

type TExtraKeys = "house_roll_call_vote_number" | "senate_roll_call_vote_number";

type TKey = TOmittedKeys | TExtraKeys;

export const BILL_INPUTS: Record<TKey, sway.IFormField<IApiBillCreator>> = {
    external_id: {
        name: "external_id",
        component: "text",
        type: "text",
        label: "Bill External Id",
        isRequired: true,
        helperText:
            "The ID of the bill from the official source (ex. congress.gov) without any spaces or punctuation (ex. hr815 NOT H.R. 815)",
    },
    external_version: {
        name: "external_version",
        component: "text",
        type: "number",
        label: "Bill External Version Number ",
        isRequired: false,
        default: "",
        helperText:
            "The numeric version (if any) of the bill (ex. Baltimore Legistar has v0, v1, etc. for bills so enter 0 or 1)",
    },

    title: {
        name: "title",
        component: "text",
        type: "text",
        label: "Bill Title",
        isRequired: true,
        helperText: "A short title for the bill.",
    },
    link: {
        name: "link",
        component: "text",
        type: "text",
        label: "Bill Link",
        isRequired: true,
        helperText: "A link to the bill itself.",
    },

    legislator_id: {
        name: "legislator_id",
        component: "select",
        type: "text",
        label: "Legislator Sponsor",
        isRequired: true,
        helperText: "The legislator that introduced the bill.",
    },
    chamber: {
        name: "chamber",
        component: "select",
        type: "text",
        label: "Chamber",
        isRequired: true,
        default: "council",
        helperText: "The chamber that introduced the legislation.",
        possibleValues: [
            { label: "council", value: "council" },
            { label: "house", value: "house" },
            { label: "senate", value: "senate" },
        ],
        disableOn: (locale: sway.ISwayLocale) => locale.city.toLowerCase() !== locale.region_name.toLowerCase(),
    },

    status: {
        name: "status",
        component: "select",
        type: "text",
        label: "Bill Status",
        isRequired: false,
        helperText:
            "The most current status of the bill. If the bill has passed the House but is in committee in the Senate, the status should be 'committee'.",
        possibleValues: [
            { label: "Committee", value: "committee" },
            { label: "Passed", value: "passed" },
            { label: "Failed", value: "failed" },
            { label: "Vetoed", value: "vetoed" },
        ],
    },
    category: {
        name: "category",
        component: "select",
        type: "text",
        label: "Category",
        isRequired: true,
        helperText: "A single category this bill belongs to.",
        possibleValues: [
            { label: "Immigration", value: "immigration" },
            { label: "Police", value: "police" },
            { label: "Health", value: "health" },
            { label: "Housing", value: "housing" },
            { label: "Infrastructure", value: "infrastructure" },
            { label: "Political Reform", value: "political reform" },
            { label: "Civil Rights", value: "civil rights" },
            { label: "Education", value: "education" },
            { label: "Economy", value: "economy" },
            { label: "Transportation", value: "transportation" },
        ],
    },

    introduced_date_time_utc: {
        name: "introduced_date_time_utc",
        component: "date",
        type: "date",
        label: "Introduced On",
        isRequired: true,
        helperText: "The date this bill was first introduced.",
    },
    withdrawn_date_time_utc: {
        name: "withdrawn_date_time_utc",
        component: "date",
        type: "date",
        label: "Withdrawn On",
        isRequired: false,
        helperText: "The date this bill was withdrawn.",
    },
    house_vote_date_time_utc: {
        name: "house_vote_date_time_utc",
        component: "date",
        type: "date",
        label: "House / Council Vote Date",
        isRequired: false,
        helperText: "The most recent date this legislation was voted on by the House.",
    },
    senate_vote_date_time_utc: {
        name: "senate_vote_date_time_utc",
        component: "date",
        type: "date",
        label: "Senate Vote Date",
        isRequired: false,
        helperText: "The most recent date this legislation was voted on by the Senate.",
        disableOn: (locale: sway.ISwayLocale) => locale.city.toLowerCase() !== locale.region_name.toLowerCase(),
    },

    house_roll_call_vote_number: {
        name: "house_roll_call_vote_number",
        component: "text",
        type: "number",
        label: "House Vote Roll Call Number ",
        isRequired: false,
        helperText: "The most recent roll call vote number for the House / Council.",
    },
    senate_roll_call_vote_number: {
        name: "senate_roll_call_vote_number",
        component: "text",
        type: "number",
        label: "Senate Vote Roll Call Number ",
        isRequired: false,
        helperText: "The most recent roll call vote number for the Senate.",
    },

    summary: {
        name: "summary",
        label: "Sway Bill Summary",
        component: "textarea",
        type: "text",
        isRequired: true,
        helperText: "Sway's short summary of the bill's contents.",
    },
};
