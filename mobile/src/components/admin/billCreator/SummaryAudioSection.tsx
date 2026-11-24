// @lat: [[mobile-bill-creator#Sections#The summary audio section]]
import React, { useState } from "react";
import { Text, View } from "react-native";
import * as DocumentPicker from "expo-document-picker";

import { directUpload } from "../../../api/directUpload";
import { GENERIC_ERROR_MESSAGE } from "../../../api/errors";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import { FormField } from "../../ui/FormField";
import { Pressable } from "../../ui/Pressable";

export interface CreatorBillAudio {
    audio_bucket_path?: string | null;
    audio_by_line?: string | null;
}

interface SummaryAudioSectionProps {
    billId: number | null;
    bill: CreatorBillAudio | undefined;
}

const AUDIO_HELP = "One field takes either an uploaded file or a link, so the audio can live somewhere else.";

const firstMessage = (errors: Record<string, unknown> | null, name: string) => {
    const messages = errors?.[name];
    if (Array.isArray(messages)) return typeof messages[0] === "string" ? messages[0] : undefined;
    return typeof messages === "string" ? messages : undefined;
};

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";

export default function SummaryAudioSection({ billId, bill }: SummaryAudioSectionProps) {
    const [audioBucketPath, setAudioBucketPath] = useState(bill?.audio_bucket_path?.trim() ?? "");
    const [audioByLine, setAudioByLine] = useState(bill?.audio_by_line?.trim() ?? "");
    const [uploading, setUploading] = useState(false);
    const [uploadError, setUploadError] = useState<string | null>(null);
    const [saved, setSaved] = useState(false);
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>("patch", Routes.bill(billId ?? 0));
    const busy = uploading || loading;

    if (billId === null) {
        return (
            <View testID="admin-summary-audio" className="px-4 mt-6">
                <Text className="text-sm italic font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Save the bill before adding audio.
                </Text>
            </View>
        );
    }

    const chooseAudio = async () => {
        const picked = await DocumentPicker.getDocumentAsync({ type: "audio/*", copyToCacheDirectory: true });
        const asset = picked.canceled ? undefined : picked.assets[0];
        if (!asset) return;
        setUploadError(null);
        setSaved(false);
        setUploading(true);
        try {
            setAudioBucketPath(
                await directUpload({
                    uri: asset.uri,
                    filename: asset.name,
                    contentType: asset.mimeType ?? "application/octet-stream",
                }),
            );
        } catch (e: unknown) {
            setUploadError(e instanceof Error ? e.message : GENERIC_ERROR_MESSAGE);
        } finally {
            setUploading(false);
        }
    };

    const save = async () => {
        setSaved(false);
        const response = await run({ audio_bucket_path: audioBucketPath.trim(), audio_by_line: audioByLine.trim() });
        if (response !== undefined) setSaved(true);
    };

    return (
        <View testID="admin-summary-audio" className="px-4 mt-6">
            <Text className="mb-1 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Audio Summary
            </Text>
            <Text className={`mb-3 ${mutedText}`}>{AUDIO_HELP}</Text>
            <Pressable
                testID="admin-summary-audio-upload"
                variant="outline"
                disabled={busy}
                accessibilityLabel={audioBucketPath ? "Upload a new audio summary" : "Upload an audio summary"}
                onPress={() => void chooseAudio()}
            >
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {uploading ? "Uploading..." : audioBucketPath ? "Upload New Audio Summary" : "Upload Audio Summary"}
                </Text>
            </Pressable>
            {uploadError ? (
                <Text
                    testID="admin-summary-audio-upload-error"
                    className="mt-1 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {uploadError}
                </Text>
            ) : null}
            <Text className={`mb-3 mt-3 font-open-sans-semibold uppercase ${mutedText}`}>
                or use an external source
            </Text>
            <FormField
                testID="admin-summary-audio-audio_bucket_path"
                label="Audio Bucket Path"
                value={audioBucketPath}
                onChangeText={setAudioBucketPath}
                placeholder="https://..."
                error={firstMessage(fieldErrors, "audio_bucket_path")}
                disabled={busy}
            />
            <FormField
                testID="admin-summary-audio-audio_by_line"
                label="Audio By"
                value={audioByLine}
                onChangeText={setAudioByLine}
                error={firstMessage(fieldErrors, "audio_by_line")}
                disabled={busy}
            />
            {errorMessage ? (
                <Text
                    testID="admin-summary-audio-error"
                    className="mb-3 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {errorMessage}
                </Text>
            ) : null}
            {saved ? (
                <Text
                    testID="admin-summary-audio-saved"
                    className="mb-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Audio saved.
                </Text>
            ) : null}
            <Pressable
                testID="admin-summary-audio-save"
                variant="default"
                disabled={busy}
                accessibilityLabel="Save the audio summary"
                onPress={() => void save()}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Saving..." : "Save Audio"}
                </Text>
            </Pressable>
        </View>
    );
}
