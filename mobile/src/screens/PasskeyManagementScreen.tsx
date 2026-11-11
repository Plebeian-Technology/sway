// @lat: [[passkey-management-page-overview#Mobile: PasskeyManagementScreen]]
import React, { useCallback, useEffect, useState } from "react";
import { ActivityIndicator, ScrollView, Text, View } from "react-native";
import { KeyRound } from "lucide-react-native";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { NoPasskeyError, passkeyAuth } from "../auth/passkeyAuth";
import { smsAuth } from "../auth/smsAuth";
import { Card } from "../components/ui/Card";
import { EmptyState } from "../components/ui/EmptyState";
import { FormField } from "../components/ui/FormField";
import { ListRow } from "../components/ui/ListRow";
import { Pressable } from "../components/ui/Pressable";
import { PHONE_INPUT_TRANSFORMER, removeNonDigits } from "../utils/phone";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

type AddStep = "idle" | "phone" | "sending" | "code" | "working";

interface Passkey {
    id: number;
    label?: string | null;
    last_used_at?: string | null;
    created_at?: string | null;
    device?: string | null;
}

const formatDate = (iso: string | null | undefined): string => {
    if (!iso) return "";
    return new Date(iso).toLocaleDateString();
};

export default function PasskeyManagementScreen() {
    const [passkeys, setPasskeys] = useState<Passkey[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
    const [addStep, setAddStep] = useState<AddStep>("idle");
    const [addPhone, setAddPhone] = useState("");
    const [addCode, setAddCode] = useState("");
    const [deviceName, setDeviceName] = useState("");
    const [addError, setAddError] = useState<string | null>(null);
    const addWorking = addStep === "sending" || addStep === "working";
    const isCodeStep = addStep === "code" || addStep === "working";

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const res = await apiClient.get<{ passkeys?: Passkey[] } | Passkey[]>(Routes.passkeys());
            const rows = Array.isArray(res) ? res : (res?.passkeys ?? []);
            setPasskeys(rows);
        } catch (e) {
            setError(e instanceof Error ? e.message : PARITY_COPY.passkey.errorLoad);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        refresh();
    }, [refresh]);

    const resetAdd = useCallback(() => {
        setAddStep("idle");
        setAddPhone("");
        setAddCode("");
        setDeviceName("");
        setAddError(null);
    }, []);

    const handleSendCode = useCallback(async () => {
        if (removeNonDigits(addPhone).length !== 10) {
            setAddError(PARITY_COPY.auth.passkeyPanel.validationPhone);
            return;
        }
        setAddStep("sending");
        setAddError(null);
        try {
            await smsAuth.requestCode(addPhone);
            setAddStep("code");
        } catch {
            setAddError(PARITY_COPY.auth.passkeyPanel.requestCodeError);
            setAddStep("phone");
        }
    }, [addPhone]);

    const handleConfirmAdd = useCallback(async () => {
        const trimmedCode = addCode.trim();
        if (!trimmedCode) {
            setAddError(PARITY_COPY.passkey.codeError);
            return;
        }
        setAddStep("working");
        setAddError(null);
        let smsVerifiedToken: string;
        try {
            const verified = await smsAuth.verifyCode(addPhone, trimmedCode);
            smsVerifiedToken = verified.sms_verified_token;
        } catch (e) {
            setAddError(e instanceof Error ? e.message : PARITY_COPY.passkey.codeError);
            setAddStep("code");
            return;
        }

        try {
            await passkeyAuth.addPasskey(smsVerifiedToken, deviceName.trim());
            resetAdd();
            await refresh();
        } catch (e) {
            const isNoPasskey = e instanceof NoPasskeyError || (e instanceof Error && e.message === "no_credential");
            const baseMsg = isNoPasskey
                ? "Passkey setup was cancelled or could not be completed."
                : e instanceof Error && e.message
                  ? e.message
                  : PARITY_COPY.passkey.addError;
            setAddCode("");
            setAddError(`${baseMsg} Please request a new code to try again.`);
            setAddStep("phone");
        }
    }, [addPhone, addCode, deviceName, resetAdd, refresh]);

    return (
        <ScrollView
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentInsetAdjustmentBehavior="automatic"
            testID="passkey-mgmt-screen"
        >
            <View className="p-6">
                <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {PARITY_COPY.passkey.title}
                </Text>
                <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mt-2">
                    {PARITY_COPY.passkey.lead}
                </Text>
            </View>

            <View className="px-4 pb-2" testID="add-passkey">
                <Card>
                    <View className="p-4 gap-3">
                        {addStep === "idle" ? (
                            <>
                                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                    {PARITY_COPY.passkey.addLead}
                                </Text>
                                <Pressable
                                    testID="add-passkey-start"
                                    variant="default"
                                    onPress={() => setAddStep("phone")}
                                    accessibilityLabel={PARITY_COPY.passkey.addCta}
                                >
                                    <View className="flex-row items-center justify-center gap-2">
                                        <KeyRound size={16} color="#fff" />
                                        <Text className="text-primary-foreground-light dark:text-primary-foreground-dark text-sm font-open-sans-semibold">
                                            {PARITY_COPY.passkey.addCta}
                                        </Text>
                                    </View>
                                </Pressable>
                            </>
                        ) : (
                            <>
                                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                    {isCodeStep ? PARITY_COPY.passkey.codeSentHint : PARITY_COPY.passkey.addPhonePrompt}
                                </Text>

                                {addStep === "phone" || addStep === "sending" ? (
                                    <FormField
                                        testID="add-passkey-phone"
                                        label={PARITY_COPY.auth.passkeyPanel.phoneLabel}
                                        value={PHONE_INPUT_TRANSFORMER.input(addPhone)}
                                        onChangeText={(text) => {
                                            setAddPhone(PHONE_INPUT_TRANSFORMER.output(text));
                                            setAddError(null);
                                        }}
                                        placeholder={PARITY_COPY.auth.passkeyPanel.phonePlaceholder}
                                        keyboardType="phone-pad"
                                        maxLength={16}
                                        disabled={addWorking}
                                    />
                                ) : null}

                                {isCodeStep ? (
                                    <>
                                        <FormField
                                            testID="add-passkey-name"
                                            label={PARITY_COPY.passkey.deviceNameLabel}
                                            value={deviceName}
                                            onChangeText={setDeviceName}
                                            placeholder={PARITY_COPY.passkey.deviceNamePlaceholder}
                                            disabled={addWorking}
                                        />
                                        <FormField
                                            testID="add-passkey-code"
                                            label={PARITY_COPY.passkey.codeLabel}
                                            value={addCode}
                                            onChangeText={(text) => {
                                                setAddCode(text);
                                                setAddError(null);
                                            }}
                                            placeholder={PARITY_COPY.passkey.codePlaceholder}
                                            keyboardType="number-pad"
                                            maxLength={6}
                                            disabled={addWorking}
                                        />
                                    </>
                                ) : null}

                                {addError ? (
                                    <Text
                                        testID="add-passkey-error"
                                        className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                                    >
                                        {addError}
                                    </Text>
                                ) : null}

                                <Pressable
                                    testID="add-passkey-confirm"
                                    variant="default"
                                    onPress={isCodeStep ? handleConfirmAdd : handleSendCode}
                                    disabled={addWorking}
                                    accessibilityLabel={
                                        isCodeStep ? PARITY_COPY.passkey.addConfirmCta : PARITY_COPY.passkey.sendCodeCta
                                    }
                                >
                                    <Text className="text-primary-foreground-light dark:text-primary-foreground-dark text-sm font-open-sans-semibold">
                                        {addWorking
                                            ? PARITY_COPY.passkey.addingLabel
                                            : isCodeStep
                                              ? PARITY_COPY.passkey.addConfirmCta
                                              : PARITY_COPY.passkey.sendCodeCta}
                                    </Text>
                                </Pressable>
                                <Pressable
                                    testID="add-passkey-cancel"
                                    variant="outline"
                                    onPress={resetAdd}
                                    disabled={addWorking}
                                    accessibilityLabel={PARITY_COPY.passkey.cancelCta}
                                >
                                    <Text className="text-foreground-light dark:text-foreground-dark text-sm font-open-sans-semibold">
                                        {PARITY_COPY.passkey.cancelCta}
                                    </Text>
                                </Pressable>
                            </>
                        )}
                    </View>
                </Card>
            </View>

            {loading ? (
                <View className="p-6">
                    <ActivityIndicator accessibilityLabel="Loading passkeys" />
                </View>
            ) : null}

            {!loading && !error && passkeys.length === 0 ? (
                <EmptyState title={PARITY_COPY.passkey.empty} testID="passkey-empty" />
            ) : null}

            {!loading && passkeys.length > 0 ? (
                <View className="px-4">
                    <Card>
                        {passkeys.map((p) => {
                            const lastUsed = p.last_used_at
                                ? `${PARITY_COPY.passkey.lastUsedPrefix} ${formatDate(p.last_used_at)}`
                                : PARITY_COPY.passkey.neverUsed;
                            const created = p.created_at
                                ? `${PARITY_COPY.passkey.createdOnPrefix} ${formatDate(p.created_at)}`
                                : "";
                            const device = `${PARITY_COPY.passkey.devicePrefix}: ${p.device ?? PARITY_COPY.passkey.deviceUnknown}`;
                            return (
                                <View key={p.id} testID={`passkey-row-${p.id}`}>
                                    <ListRow label={p.label ?? "Passkey"} accessibilityLabel={p.label ?? "Passkey"} />
                                    <View className="px-4 pb-3">
                                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                            {device}
                                        </Text>
                                        {created ? (
                                            <Text
                                                className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                                                style={{ fontVariant: ["tabular-nums"] }}
                                            >
                                                {created}
                                            </Text>
                                        ) : null}
                                        <Text
                                            className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                                            style={{ fontVariant: ["tabular-nums"] }}
                                        >
                                            {lastUsed}
                                        </Text>
                                    </View>
                                </View>
                            );
                        })}
                    </Card>
                </View>
            ) : null}

            {error ? (
                <Text
                    testID="passkey-error"
                    className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark p-6"
                >
                    {error}
                </Text>
            ) : null}
        </ScrollView>
    );
}
