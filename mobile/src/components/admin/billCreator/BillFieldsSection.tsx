// @lat: [[mobile-bill-creator#Sections#The bill fields section]]
import React, { useState } from "react";
import { Linking, Text, TextInput, View } from "react-native";

import { Routes } from "../../../api/routes";
import { Markdown } from "../../Markdown";
import { FormField } from "../../ui/FormField";
import { Pressable } from "../../ui/Pressable";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import { useBootstrap } from "../../../state/BootstrapContext";
import { toFormattedLocaleName, type Locale } from "../../../utils/locale";
import NewsEvidenceControls, { type EvidenceArticle, type NewsUsage } from "./NewsEvidenceControls";

export interface CreatorBill {
    id: number | null;
    external_id: string | null;
    external_version?: string | null;
    title: string | null;
    link?: string | null;
    chamber?: string | null;
    status?: string | null;
    active?: boolean | null;
    introduced_date_time_utc?: string | null;
    house_vote_date_time_utc?: string | null;
    senate_vote_date_time_utc?: string | null;
    legislator_id?: number | null;
    sway_locale_id?: number | null;
    summary?: string | null;
    vote?: {
        house_roll_call_vote_number?: number | string | null;
        senate_roll_call_vote_number?: number | string | null;
    } | null;
}

export interface CreatorLegislator {
    id: number;
    first_name: string;
    last_name: string;
    district?: { region_code: string; number: number } | null;
}

type CreatorLocale = Locale & { default_bill_chamber?: string | null; bill_chambers?: string[] | null };

interface Option {
    label: string;
    value: string;
}

interface Fields {
    sway_locale_id: string;
    external_id: string;
    external_version: string;
    title: string;
    link: string;
    legislator_id: string;
    chamber: string;
    status: string;
    introduced_date_time_utc: string;
    house_vote_date_time_utc: string;
    senate_vote_date_time_utc: string;
    house_roll_call_vote_number: string;
    senate_roll_call_vote_number: string;
    summary: string;
}

type DateFieldName = "introduced_date_time_utc" | "house_vote_date_time_utc" | "senate_vote_date_time_utc";

const DATE_FIELDS: DateFieldName[] = [
    "introduced_date_time_utc",
    "house_vote_date_time_utc",
    "senate_vote_date_time_utc",
];

const CHAMBER_OPTIONS: Option[] = [
    { label: "council", value: "council" },
    { label: "house", value: "house" },
    { label: "senate", value: "senate" },
];

const STATUS_OPTIONS: Option[] = [
    { label: "Committee", value: "committee" },
    { label: "Passed", value: "passed" },
    { label: "Failed", value: "failed" },
    { label: "Vetoed", value: "vetoed" },
];

const LOCALE_MESSAGE = "Please select a locale before saving.";

const REQUIRED_FIELDS: readonly [keyof Fields, string][] = [
    ["status", "Please select the bill status before saving."],
    ["chamber", "Please select the bill chamber before saving."],
    ["legislator_id", "Please select the bill sponsor before saving."],
];

const DATE_MESSAGE = "Enter the date as YYYY-MM-DD.";

const MARKDOWN_GUIDE_URL = "https://www.markdownguide.org/basic-syntax";

const asText = (value: string | number | null | undefined) =>
    value === null || value === undefined ? "" : String(value);

const asDateText = (value: string | null | undefined) => (value ? value.slice(0, 10) : "");

const isDateText = (text: string) => /^\d{4}-\d{2}-\d{2}$/.test(text) && !Number.isNaN(new Date(text).getTime());

const titleize = (text: string) =>
    text
        .toLowerCase()
        .split(" ")
        .filter(Boolean)
        .map((word) => word[0].toUpperCase() + word.slice(1))
        .join(" ");

const sponsorLabel = (legislator: CreatorLegislator) => {
    const name = `${titleize(legislator.last_name)}, ${titleize(legislator.first_name)}`;
    return legislator.district ? `${name} (${legislator.district.region_code} - ${legislator.district.number})` : name;
};

const fieldsFromBill = (bill: CreatorBill | undefined, locale: CreatorLocale | undefined): Fields => ({
    sway_locale_id: asText(bill?.sway_locale_id ?? locale?.id),
    external_id: asText(bill?.external_id).trim(),
    external_version: asText(bill?.external_version).trim(),
    title: asText(bill?.title).trim(),
    link: asText(bill?.link).trim(),
    legislator_id: asText(bill?.legislator_id),
    chamber: bill?.chamber || asText(locale?.default_bill_chamber),
    status: STATUS_OPTIONS.find((option) => option.value === bill?.status?.trim())?.value ?? "committee",
    introduced_date_time_utc: asDateText(bill?.introduced_date_time_utc),
    house_vote_date_time_utc: asDateText(bill?.house_vote_date_time_utc),
    senate_vote_date_time_utc: asDateText(bill?.senate_vote_date_time_utc),
    house_roll_call_vote_number: asText(bill?.vote?.house_roll_call_vote_number),
    senate_roll_call_vote_number: asText(bill?.vote?.senate_roll_call_vote_number),
    summary: asText(bill?.summary),
});

const firstMessage = (errors: Record<string, unknown> | null, name: string) => {
    const messages = errors?.[name];
    if (Array.isArray(messages)) return typeof messages[0] === "string" ? messages[0] : undefined;
    return typeof messages === "string" ? messages : undefined;
};

const publicationReasons = (errors: Record<string, unknown> | null) =>
    Array.isArray(errors?.errors) ? errors.errors.filter((reason): reason is string => typeof reason === "string") : [];

interface SummaryFieldProps {
    value: string;
    onChange: (value: string) => void;
    disabled: boolean;
    errors: string[];
}

// @lat: [[mobile-bill-creator#Sections#The bill fields section#The summary field]]
const SummaryField = ({ value, onChange, disabled, errors }: SummaryFieldProps) => (
    <View testID="admin-bill-fields-summary" className="mb-4">
        <Text className="mb-1 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
            Sway Bill Summary *
        </Text>
        <Text className="mb-2 text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {"Sway's short summary of the bill's contents."}
        </Text>
        <TextInput
            testID="admin-bill-fields-summary-input"
            accessibilityLabel="Sway Bill Summary"
            multiline
            value={value}
            onChangeText={onChange}
            editable={!disabled}
            className="min-h-48 rounded-md border border-border-light dark:border-border-dark bg-input-light dark:bg-input-dark p-3 font-open-sans-light text-foreground-light dark:text-foreground-dark"
        />
        {errors.map((error, index) => (
            <Text
                key={`${index}-${error}`}
                testID={index === 0 ? "admin-bill-fields-summary-error" : `admin-bill-fields-summary-error-${index}`}
                className="mt-1 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
            >
                {error}
            </Text>
        ))}
        <Pressable
            testID="admin-bill-fields-summary-guide"
            variant="ghost"
            accessibilityRole="link"
            onPress={() => void Linking.openURL(MARKDOWN_GUIDE_URL)}
        >
            <Text className="text-xs font-open-sans-semibold uppercase text-accent-light dark:text-accent-dark underline">
                Markdown Syntax Guide
            </Text>
        </Pressable>
        <View
            testID="admin-bill-fields-summary-preview"
            className="rounded-md border border-border-light dark:border-border-dark p-3"
        >
            <Markdown content={value} className="text-sm text-foreground-light dark:text-foreground-dark" />
        </View>
    </View>
);

interface ChoiceFieldProps {
    name: string;
    label: string;
    options: Option[];
    value: string;
    onChange: (value: string) => void;
    disabled?: boolean;
    error?: string;
}

const ChoiceField = ({ name, label, options, value, onChange, disabled = false, error }: ChoiceFieldProps) => {
    const [open, setOpen] = useState(false);
    const selected = options.find((option) => option.value === value);
    const testID = `admin-bill-fields-${name}`;

    return (
        <View testID={testID} className="mb-4">
            <Text className="mb-2 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {label}
            </Text>
            <Pressable
                testID={`${testID}-toggle`}
                variant="outline"
                disabled={disabled}
                accessibilityLabel={`${label}, ${selected?.label ?? "not selected"}`}
                accessibilityState={{ expanded: open }}
                onPress={() => setOpen((isOpen) => !isOpen)}
            >
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {selected?.label ?? "Select..."}
                </Text>
            </Pressable>
            {open
                ? options.map((option) => (
                      <Pressable
                          key={option.value}
                          testID={`${testID}-option-${option.value}`}
                          variant="ghost"
                          accessibilityState={{ selected: option.value === value }}
                          onPress={() => {
                              onChange(option.value);
                              setOpen(false);
                          }}
                      >
                          <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
                              {option.label}
                          </Text>
                      </Pressable>
                  ))
                : null}
            {error ? (
                <Text
                    testID={`${testID}-error`}
                    className="mt-1 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {error}
                </Text>
            ) : null}
        </View>
    );
};

interface BillFieldsSectionProps {
    billId: number | null;
    bill: CreatorBill | undefined;
    legislators: CreatorLegislator[];
    newsArticles?: EvidenceArticle[];
    onSaved: (bill: CreatorBill) => void;
}

export default function BillFieldsSection({
    billId,
    bill,
    legislators,
    newsArticles = [],
    onSaved,
}: BillFieldsSectionProps) {
    const { bootstrap } = useBootstrap();
    const locales = (bootstrap?.sway_locales ?? []) as CreatorLocale[];
    const [fields, setFields] = useState<Fields>(() =>
        fieldsFromBill(bill, (bootstrap?.locale ?? undefined) as CreatorLocale | undefined),
    );
    const [formMessage, setFormMessage] = useState<string | null>(null);
    const [dateErrors, setDateErrors] = useState<Partial<Record<DateFieldName, string>>>({});
    const [saved, setSaved] = useState(false);
    const [newsUsage, setNewsUsage] = useState<NewsUsage>("none");
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<CreatorBill>(
        billId === null ? "post" : "patch",
        billId === null ? Routes.bills() : Routes.bill(billId),
    );

    const selectedLocale = locales.find((locale) => String(locale.id) === fields.sway_locale_id);
    const chambers = selectedLocale?.bill_chambers ?? [];
    const setField = (name: keyof Fields) => (value: string) => setFields((current) => ({ ...current, [name]: value }));

    const localeOptions = locales.map((locale) => ({
        label: toFormattedLocaleName(locale.name),
        value: String(locale.id),
    }));
    const sponsorOptions = legislators
        .map((legislator) => ({ label: sponsorLabel(legislator), value: String(legislator.id) }))
        .sort((a, b) => a.label.localeCompare(b.label));

    const reasons = publicationReasons(fieldErrors);
    const errorFor = (name: string) => (reasons.length > 0 ? undefined : firstMessage(fieldErrors, name));

    const save = async () => {
        setSaved(false);
        if (!fields.sway_locale_id) {
            setFormMessage(LOCALE_MESSAGE);
            return;
        }
        const requiredMessage = REQUIRED_FIELDS.find(([name]) => !fields[name])?.[1];
        if (requiredMessage) {
            setFormMessage(requiredMessage);
            return;
        }
        const badDates = Object.fromEntries(
            DATE_FIELDS.filter((name) => fields[name] !== "" && !isDateText(fields[name])).map((name) => [
                name,
                DATE_MESSAGE,
            ]),
        );
        setDateErrors(badDates);
        if (Object.keys(badDates).length > 0) {
            setFormMessage(null);
            return;
        }
        setFormMessage(null);

        const dates = Object.fromEntries(
            DATE_FIELDS.map((name) => [name, fields[name] === "" ? null : new Date(fields[name]).toISOString()]),
        );
        const response = await run({
            ...fields,
            ...dates,
            sway_locale_id: Number(fields.sway_locale_id),
            legislator_id: Number(fields.legislator_id),
            active: bill?.active ?? true,
            news_usage: newsUsage,
            source_uses: [],
        });
        if (response) {
            setFields(fieldsFromBill(response, selectedLocale));
            setSaved(true);
            onSaved(response);
        }
    };

    const textField = (name: keyof Fields, label: string, disabled = false) => (
        <FormField
            testID={`admin-bill-fields-${name}`}
            label={label}
            value={fields[name]}
            onChangeText={setField(name)}
            error={dateErrors[name as DateFieldName] ?? errorFor(name)}
            disabled={loading || disabled}
            placeholder={DATE_FIELDS.includes(name as DateFieldName) ? "YYYY-MM-DD" : undefined}
        />
    );

    return (
        <View testID="admin-bill-fields" className="px-4">
            <ChoiceField
                name="sway_locale_id"
                label="Locale"
                options={localeOptions}
                value={fields.sway_locale_id}
                onChange={(value) => {
                    const locale = locales.find((candidate) => String(candidate.id) === value);
                    setFields((current) => ({
                        ...current,
                        sway_locale_id: value,
                        chamber: asText(locale?.default_bill_chamber),
                    }));
                }}
                error={errorFor("sway_locale_id")}
            />
            {textField("external_id", "Bill External Id")}
            {textField("external_version", "Bill External Version Number")}
            {textField("title", "Bill Title")}
            {textField("link", "Bill Link")}
            <ChoiceField
                name="legislator_id"
                label="Legislator Sponsor"
                options={sponsorOptions}
                value={fields.legislator_id}
                onChange={setField("legislator_id")}
                error={errorFor("legislator_id")}
            />
            <ChoiceField
                name="chamber"
                label="Chamber"
                options={CHAMBER_OPTIONS}
                value={fields.chamber}
                onChange={setField("chamber")}
                disabled={chambers.length === 1}
                error={errorFor("chamber")}
            />
            <ChoiceField
                name="status"
                label="Bill Status"
                options={STATUS_OPTIONS}
                value={fields.status}
                onChange={setField("status")}
                error={errorFor("status")}
            />
            {textField("introduced_date_time_utc", "Introduced On")}
            {textField("house_vote_date_time_utc", "House / Council Vote Date")}
            {textField(
                "senate_vote_date_time_utc",
                "Senate Vote Date",
                chambers.length > 0 && !chambers.includes("senate"),
            )}
            {textField("house_roll_call_vote_number", "House Vote Roll Call Number")}
            {textField("senate_roll_call_vote_number", "Senate Vote Roll Call Number")}
            <SummaryField
                value={fields.summary}
                onChange={setField("summary")}
                disabled={loading}
                errors={reasons.length > 0 ? reasons : [errorFor("summary")].filter((error) => error !== undefined)}
            />
            <NewsEvidenceControls
                summary={fields.summary}
                newsUsage={newsUsage}
                onChangeNewsUsage={setNewsUsage}
                articles={newsArticles}
                disabled={loading}
            />
            {formMessage || errorMessage ? (
                <Text
                    testID="admin-bill-fields-error"
                    className="mb-3 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {formMessage ?? errorMessage}
                </Text>
            ) : null}
            {saved ? (
                <Text
                    testID="admin-bill-fields-saved"
                    className="mb-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Bill saved.
                </Text>
            ) : null}
            <Pressable
                testID="admin-bill-fields-save"
                variant="default"
                disabled={loading}
                accessibilityLabel="Save the bill"
                onPress={() => void save()}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Saving..." : "Save Bill"}
                </Text>
            </Pressable>
        </View>
    );
}
