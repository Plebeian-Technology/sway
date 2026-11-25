// @lat: [[mobile-bill-creator#Sections#The organizations section]]
import React, { useMemo, useRef, useState } from "react";
import { Alert, Image, Switch, Text, TextInput, View } from "react-native";
import * as DocumentPicker from "expo-document-picker";

import { directUpload } from "../../../api/directUpload";
import { GENERIC_ERROR_MESSAGE } from "../../../api/errors";
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
    icon_signed_id?: string;
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
    const [uploadingCount, setUploadingCount] = useState(0);
    const nextTempId = useRef(-1);
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>(
        "post",
        Routes.adminOrganizations(tabKey),
    );

    const positionIdOf = (organizationId: number) =>
        bill?.organizations
            ?.find((organization) => organization.id === organizationId)
            ?.positions?.find((position) => position.bill_id === billId)?.id;

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
        if (uploadingCount > 0) return;
        setSaved(false);
        if (billId === null) {
            setFormMessage(UNSAVED_BILL_MESSAGE);
            return;
        }
        setFormMessage(null);
        const response = await run({
            bill_id: billId,
            organizations: rows.map(({ value, label, support, summary, icon_url, icon_signed_id }) => ({
                value,
                label,
                support,
                summary,
                icon_url,
                ...(icon_signed_id ? { icon_signed_id } : {}),
            })),
        });
        if (response !== undefined) {
            setSaved(true);
            void refresh();
        }
    };

    const removeRow = (index: number) => {
        setSaved(false);
        setRows((current) => current.filter((_, i) => i !== index));
        void refresh();
    };

    const saveBusy = loading || uploadingCount > 0;
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
                        onUploading={(uploading) => setUploadingCount((count) => count + (uploading ? 1 : -1))}
                        tabKey={tabKey}
                        positionId={positionIdOf(row.value)}
                        onChange={(change) => updateRow(index, change)}
                        onRenamed={refresh}
                        onRemoved={() => removeRow(index)}
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
                disabled={saveBusy}
                accessibilityLabel="Save Supporting/Opposing Arguments"
                onPress={() => void save()}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {saveBusy ? "Saving..." : "Save Supporting/Opposing Arguments"}
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
    onUploading: (uploading: boolean) => void;
    tabKey: string;
    positionId: number | undefined;
    onChange: (change: Partial<OrganizationRow>) => void;
    onRenamed: () => void;
    onRemoved: () => void;
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

function OrganizationRowCard({
    index,
    row,
    error,
    disabled,
    onUploading,
    tabKey,
    positionId,
    onChange,
    onRenamed,
    onRemoved,
}: OrganizationRowCardProps) {
    const testID = `admin-organizations-row-${index}`;
    const canRename = row.value > 0;
    const [renaming, setRenaming] = useState(false);
    const [nameDraft, setNameDraft] = useState(row.label);
    const rename = useAdminMutation<unknown>("patch", Routes.adminOrganization(row.value));
    const removal = useAdminMutation<unknown>("delete", Routes.adminOrganizationBillPosition(positionId ?? 0, tabKey));
    const [uploadingIcon, setUploadingIcon] = useState(false);
    const [iconError, setIconError] = useState<string | null>(null);
    const busy = disabled || rename.loading || removal.loading || uploadingIcon;

    const chooseIcon = async () => {
        const picked = await DocumentPicker.getDocumentAsync({ type: "image/*", copyToCacheDirectory: true });
        const asset = picked.canceled ? undefined : picked.assets[0];
        if (!asset) return;
        setIconError(null);
        setUploadingIcon(true);
        onUploading(true);
        try {
            const signedId = await directUpload({
                uri: asset.uri,
                filename: asset.name,
                contentType: asset.mimeType ?? "application/octet-stream",
            });
            onChange({ icon_signed_id: signedId, icon_url: asset.uri });
        } catch (e: unknown) {
            setIconError(e instanceof Error ? e.message : GENERIC_ERROR_MESSAGE);
        } finally {
            setUploadingIcon(false);
            onUploading(false);
        }
    };

    const startRename = () => {
        setNameDraft(row.label);
        setRenaming(true);
    };

    const saveRename = async () => {
        const name = nameDraft.trim();
        if (name === "" || name === row.label) {
            setRenaming(false);
            return;
        }
        const response = await rename.run({ name });
        if (response !== undefined) {
            onChange({ label: name });
            setRenaming(false);
            onRenamed();
        }
    };

    const remove = async () => {
        if (positionId !== undefined && (await removal.run()) === undefined) return;
        onRemoved();
    };

    const confirmRemove = () => {
        Alert.alert("Remove organization?", `Remove ${row.label} from this bill? Its position is unpublished.`, [
            { text: "Keep", style: "cancel" },
            { text: "Remove", style: "destructive", onPress: () => void remove() },
        ]);
    };

    return (
        <View testID={testID} className="mb-4 rounded-lg border border-border-light p-4 dark:border-border-dark">
            {renaming ? (
                <View>
                    <TextInput
                        testID={`${testID}-rename-input`}
                        value={nameDraft}
                        onChangeText={setNameDraft}
                        editable={!busy}
                        accessibilityLabel={`Rename ${row.label}`}
                        className="rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark"
                        style={{ minHeight: 44 }}
                    />
                    <Text className="mt-1 text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        Renames this organization for every bill in this locale.
                    </Text>
                    <View className="mt-2 flex-row gap-2">
                        <Pressable
                            testID={`${testID}-rename-save`}
                            variant="default"
                            disabled={busy}
                            accessibilityLabel={`Save new name for ${row.label}`}
                            onPress={() => void saveRename()}
                        >
                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                {rename.loading ? "Renaming..." : "Save name"}
                            </Text>
                        </Pressable>
                        <Pressable
                            testID={`${testID}-rename-cancel`}
                            variant="ghost"
                            disabled={busy}
                            accessibilityLabel={`Cancel renaming ${row.label}`}
                            onPress={() => setRenaming(false)}
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                Cancel
                            </Text>
                        </Pressable>
                    </View>
                    <RowError testID={`${testID}-rename-error`} message={rename.errorMessage} />
                </View>
            ) : (
                <View className="flex-row items-center justify-between gap-2">
                    <Text className="flex-1 text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {row.label}
                    </Text>
                    {canRename ? (
                        <Pressable
                            testID={`${testID}-rename`}
                            variant="ghost"
                            disabled={busy}
                            accessibilityLabel={`Rename ${row.label}`}
                            onPress={startRename}
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                Rename
                            </Text>
                        </Pressable>
                    ) : null}
                </View>
            )}
            <RowError testID={`${testID}-label-error`} message={error?.label} />

            <Text className="mt-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Icon
            </Text>
            <View className="mt-1 flex-row items-center gap-3">
                <View className="h-14 w-14 items-center justify-center overflow-hidden rounded-lg border border-border-light dark:border-border-dark">
                    {row.icon_url ? (
                        <Image
                            source={{ uri: row.icon_url }}
                            accessibilityLabel={`${row.label} icon`}
                            resizeMode="contain"
                            style={{ width: 56, height: 56 }}
                        />
                    ) : (
                        <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                            No icon
                        </Text>
                    )}
                </View>
                <Pressable
                    testID={`${testID}-icon-upload`}
                    variant="outline"
                    disabled={busy}
                    accessibilityLabel={`${row.icon_url ? "Update" : "Add"} icon for ${row.label}`}
                    onPress={() => void chooseIcon()}
                >
                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {uploadingIcon ? "Uploading..." : row.icon_url ? "Update icon" : "Add icon"}
                    </Text>
                </Pressable>
                {row.icon_url ? (
                    <Pressable
                        testID={`${testID}-icon-remove`}
                        variant="ghost"
                        disabled={busy}
                        accessibilityLabel={`Remove icon for ${row.label}`}
                        onPress={() => onChange({ icon_signed_id: undefined, icon_url: null })}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Remove
                        </Text>
                    </Pressable>
                ) : null}
            </View>
            <RowError testID={`${testID}-icon-upload-error`} message={iconError} />
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

            <Pressable
                testID={`${testID}-remove`}
                variant="outline"
                disabled={busy}
                accessibilityLabel={`Remove ${row.label}`}
                onPress={confirmRemove}
                className="mt-4"
            >
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {removal.loading ? "Removing..." : "Remove organization"}
                </Text>
            </Pressable>
            <RowError testID={`${testID}-remove-error`} message={removal.errorMessage} />
        </View>
    );
}
