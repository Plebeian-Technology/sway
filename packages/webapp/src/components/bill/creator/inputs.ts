import { sway } from "sway";

export const BILL_INPUTS: sway.IFormField[][] = [
    [
        {
            name: "externalId",
            component: "text",
            type: "text",
            label: "Bill External Id",
            isRequired: true,
            helperText:
                "The ID of the bill from the official source (ex. congress.gov).",
        },
        {
            name: "externalVersion",
            component: "text",
            type: "text",
            label: "Bill External Version",
            isRequired: false,
            default: "",
            helperText:
                "The Version (if any) of the bill from Baltimore Legisatr",
        },
    ],
    [
        {
            name: "firestoreId",
            component: "generatedText",
            type: "text",
            generateFields: ["externalId", "externalVersion"],
            joiner: "v",
            label: "Generated Firestore ID",
            isRequired: true,
            disabled: true,
            helperText: "The generated database ID.",
        },
        {
            name: "title",
            component: "text",
            type: "text",
            label: "Bill Title",
            isRequired: true,
            helperText: "A short title for the bill.",
        },
    ],
    [
        {
            name: "link",
            component: "text",
            type: "text",
            label: "Bill Link",
            isRequired: true,
            helperText: "A link to the bill itself.",
        },
        {
            name: "sponsorExternalId",
            component: "select",
            type: "text",
            label: "Legislator Sponsor External Id",
            isRequired: true,
            helperText: "The ID of the legislator that introduced the bill.",
        },
    ],
    [
        {
            name: "localeName",
            component: "select",
            type: "text",
            label: "Locale Name",
            isRequired: true,
            helperText: "The jurisdiction of this legislation.",
        },
        {
            name: "chamber",
            component: "text",
            type: "text",
            label: "Chamber",
            isRequired: true,
            default: "council",
            disabled: true,
            helperText: "The chamber that introduced the legislation.",
        },
    ],
    [
        {
            name: "swaySummary",
            component: "textarea",
            type: "text",
            label: "Sway Bill Summary",
            isRequired: true,
            helperText: "Sway's short summary of the bill's contents.",
        },
        {
            name: "swaySummaryPreview",
            component: "textarea",
            type: "text",
            label: "Sway Bill Summary Preview",
            isRequired: true,
            helperText:
                "A preview of how the summary will be displayed to users.",
        },
    ],
    [
        {
            name: "relatedBillIds",
            component: "text",
            type: "text",
            label: "Related Bill IDs",
            isRequired: false,
            helperText: "Official IDs of related bills.",
        },
    ],
    [
        {
            name: "organizations",
            component: "select",
            type: "text",
            label: "Organizations",
            isRequired: false,
        },
    ],
    [
        {
            name: "supporters",
            component: "select",
            type: "text",
            label: "Supporters",
            isRequired: false,
            multi: true,
        },
        {
            name: "opposers",
            component: "select",
            type: "text",
            label: "Opposers",
            isRequired: false,
            multi: true,
        },
        {
            name: "abstainers",
            component: "select",
            type: "text",
            label: "Abstainers",
            isRequired: false,
            multi: true,
        },
    ],
];
