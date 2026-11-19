// @lat: [[mobile-bill-creator#Sections#The organizations section]]
import React, { useMemo, useRef, useState } from "react";
import { Switch, Text, TextInput, View } from "react-native";

import { Routes } from "../../../api/routes";
import { Pressable } from "../../ui/Pressable";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";

interface CreatorOrganizationPosition {
    id: number;
    bill_id: number;
    support: string | null;
    summary: string | null;
}

interface CreatorOrganization {
    id: number;
    name: string;
    icon_url: string | null;
    positions?: CreatorOrganizationPosition[];
}

interface OrganizationRow {
    value: number;
    label: string;
    support: string;
    summary: string;
    icon_url: string | null;
}

type OrganizationRowError = Partial<Record<keyof OrganizationRow, string | null>>;

const FOR = "FOR";
const AGAINST = "AGAINST";
const ABSTAIN = "ABSTAIN";

const SUPPORT_LABELS: Record<string, string> = { [FOR]: "For", [AGAINST]: "Against", [ABSTAIN]: "Abstain" };

const UNSAVED_BILL_MESSAGE = "Save the bill before saving organizations.";
const SAVED_MESSAGE = "Supporting/Opposing Arguments Saved";
const REFUSAL_FALLBACK = "Error Saving Supporting/Opposing Arguments";

const normalizeName = (name: string) => name.replace(/\s+/g, " ").trim();

const toRow = (organization: CreatorOrganization, billId: number | null): OrganizationRow => {
    const position = organization.positions?.find((p) => p.bill_id === billId);
    return {
        value: organization.id,
        label: organization.name,
        support: position?.support ?? FOR,
        summary: position?.summary ?? "",
        icon_url: organization.icon_url ?? null,
    };
};

const rowErrorsFrom = (fieldErrors: Record<string, unknown> | null): (OrganizationRowError | undefined)[] =>
    Array.isArray(fieldErrors?.organizations) ? (fieldErrors.organizations as OrganizationRowError[]) : [];

export default function OrganizationsSection({ billId, data, refresh }: BillCreatorTabProps) {
    const bill = data.bill as { organizations?: CreatorOrganization[] } | undefined;
    const tabKey = typeof data.tab_key === "string" ? data.tab_key : "positions";

    const [rows, setRows] = useState<OrganizationRow[]>(() =>
        (bill?.organizations ?? []).map((organization) => toRow(organization, billId)),
    );
    const [query, setQuery] = useState("");
    const [open, setOpen] = useState(false);
    const [formMessage, setFormMessage] = useState<string | null>(null);
    const [saved, setSaved] = useState(false);
    const nextTempId = useRef(-1);
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>(
        "post",
        Routes.adminOrganizations(tabKey),
    );

    const options = useMemo(
        () => ((data.organizations ?? []) as CreatorOrganization[]).map((organization) => toRow(organization, null)),
        [data.organizations],
    );
    const normalizedQuery = normalizeName(query);

    const matches = useMemo(() => {
        const selectedIds = new Set(rows.map((row) => row.value));
        const lower = normalizedQuery.toLowerCase();
        return options.filter((option) => !selectedIds.has(option.value) && option.label.toLowerCase().includes(lower));
    }, [options, rows, normalizedQuery]);

    const canCreate =
        normalizedQuery.length > 0 &&
        ![...rows, ...options].some(
            (organization) => normalizeName(organization.label).toLowerCase() === normalizedQuery.toLowerCase(),
        );

    const updateRow = (index: number, change: Partial<OrganizationRow>) => {
        setSaved(false);
        setRows((current) => current.map((row, i) => (i === index ? { ...row, ...change } : row)));
    };

    const appendRow = (row: OrganizationRow) => {
        setSaved(false);
        setRows((current) => [...current, row]);
        setQuery("");
        setOpen(false);
    };

    const createRow = () => {
        appendRow({ value: nextTempId.current--, label: normalizedQuery, support: FOR, summary: "", icon_url: null });
    };

    const submitSearch = () => {
        if (matches.length > 0) {
            appendRow(matches[0]);
        } else if (canCreate) {
            createRow();
        }
    };

    const save = async () => {
        setSaved(false);
        if (billId === null) {
            setFormMessage(UNSAVED_BILL_MESSAGE);
            return;
        }
        setFormMessage(null);
        const response = await run({
            bill_id: billId,
            organizations: rows.map(({ value, label, support, summary, icon_url }) => ({
                value,
                label,
                support,
                summary,
                icon_url,
            })),
        });
        if (response !== undefined) {
            setSaved(true);
            void refresh();
        }
    };

    const rowErrors = errorMessage === null ? [] : rowErrorsFrom(fieldErrors);
    const shownError = formMessage ?? (errorMessage === null ? undefined : errorMessage || REFUSAL_FALLBACK);

    return (
        <View testID="admin-organizations" className="px-4">
            <Text className="mb-2 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Organizations (optional)
            </Text>
            <TextInput
                testID="admin-organizations-search"
                value={query}
                placeholder="Search or create an organization..."
                accessibilityLabel="Search or create an organization"
                onChangeText={(text) => {
                    setQuery(text);
                    setOpen(true);
                }}
                onFocus={() => setOpen(true)}
                onSubmitEditing={submitSearch}
                returnKeyType="done"
                className="rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark"
                style={{ minHeight: 44 }}
            />
            {open ? (
                <View className="mt-1">
                    {matches.map((option) => (
                        <Pressable
                            key={option.value}
                            testID={`admin-organizations-option-${option.value}`}
                            variant="ghost"
                            accessibilityLabel={`Add ${option.label}`}
                            onPress={() => appendRow(option)}
                            className="items-start"
                        >
                            <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                {option.label}
                            </Text>
                        </Pressable>
                    ))}
                    {canCreate ? (
                        <Pressable
                            testID="admin-organizations-create"
                            variant="ghost"
                            accessibilityLabel={`Create ${normalizedQuery}`}
                            onPress={createRow}
                            className="items-start"
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {`Create “${normalizedQuery}”`}
                            </Text>
                        </Pressable>
                    ) : null}
                </View>
            ) : null}
            <Text className="mb-4 mt-2 text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                Add an existing organization from this locale, or type a name and create a new one. Each selected
                organization appears below with its own sub-form.
            </Text>
            {rows.length === 0 ? (
                <Text className="mb-4 text-sm italic font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    No organizations selected yet — add one above.
                </Text>
            ) : (
                rows.map((row, index) => (
                    <OrganizationRowCard
                        key={row.value}
                        index={index}
                        row={row}
                        error={rowErrors[index]}
                        disabled={loading}
                        onChange={(change) => updateRow(index, change)}
                    />
                ))
            )}
            {shownError ? (
                <Text
                    testID="admin-organizations-error"
                    className="mb-3 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {shownError}
                </Text>
            ) : null}
            {saved ? (
                <Text
                    testID="admin-organizations-saved"
                    className="mb-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    {SAVED_MESSAGE}
                </Text>
            ) : null}
            <Pressable
                testID="admin-organizations-save"
                variant="default"
                disabled={loading}
                accessibilityLabel="Save Supporting/Opposing Arguments"
                onPress={() => void save()}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Saving..." : "Save Supporting/Opposing Arguments"}
                </Text>
            </Pressable>
        </View>
    );
}

interface OrganizationRowCardProps {
    index: number;
    row: OrganizationRow;
    error?: OrganizationRowError;
    disabled: boolean;
    onChange: (change: Partial<OrganizationRow>) => void;
}

function RowError({ testID, message }: { testID: string; message?: string | null }) {
    if (!message) return null;
    return (
        <Text
            testID={testID}
            className="mt-1 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
        >
            {message}
        </Text>
    );
}

function OrganizationRowCard({ index, row, error, disabled, onChange }: OrganizationRowCardProps) {
    const testID = `admin-organizations-row-${index}`;
    return (
        <View testID={testID} className="mb-4 rounded-lg border border-border-light p-4 dark:border-border-dark">
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {row.label}
            </Text>
            <RowError testID={`${testID}-label-error`} message={error?.label} />
            <RowError testID={`${testID}-icon-error`} message={error?.icon_url} />

            <Text className="mt-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Position
            </Text>
            <View className="mt-1 flex-row items-center gap-3">
                <Switch
                    testID={`${testID}-support`}
                    value={row.support === FOR}
                    disabled={disabled}
                    onValueChange={(isFor) => onChange({ support: isFor ? FOR : AGAINST })}
                    accessibilityLabel={`${row.label} support`}
                />
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {SUPPORT_LABELS[row.support] ?? row.support}
                </Text>
            </View>
            <RowError testID={`${testID}-support-error`} message={error?.support} />

            <Text className="mt-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {`${row.label} position summary`}
            </Text>
            <TextInput
                testID={`${testID}-summary`}
                value={row.summary}
                onChangeText={(summary) => onChange({ summary })}
                editable={!disabled}
                multiline
                numberOfLines={6}
                accessibilityLabel={`${row.label} position summary`}
                className={`mt-1 rounded-md border px-4 py-3 bg-input-light dark:bg-input-dark font-open-sans-light text-foreground-light dark:text-foreground-dark ${
                    error?.summary
                        ? "border-destructive-light dark:border-destructive-dark"
                        : "border-border-light dark:border-border-dark"
                }`}
                style={{ minHeight: 120, textAlignVertical: "top" }}
            />
            <Text className="mt-1 text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {`${row.label}’s opinion of the bill (markdown supported).`}
            </Text>
            <RowError testID={`${testID}-summary-error`} message={error?.summary} />
        </View>
    );
}
