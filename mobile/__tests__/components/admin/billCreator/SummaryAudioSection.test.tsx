import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { patch: (...args: unknown[]) => mockApiPatch(...args) },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

const mockGetDocumentAsync = jest.fn();
jest.mock("expo-document-picker", () => ({
    getDocumentAsync: (...args: unknown[]) => mockGetDocumentAsync(...args),
}));

const mockDirectUpload = jest.fn();
jest.mock("../../../../src/api/directUpload", () => ({
    directUpload: (...args: unknown[]) => mockDirectUpload(...args),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import SummaryAudioSection from "../../../../src/components/admin/billCreator/SummaryAudioSection";

const pickedAudio = { uri: "file:///cache/summary.mp3", name: "summary.mp3", mimeType: "audio/mpeg", size: 10 };

const typeInto = (name: string, text: string) =>
    fireEvent.changeText(screen.getByTestId(`admin-summary-audio-${name}-input`), text);

// @lat: [[mobile-bill-creator#Sections#The summary audio section]]
describe("SummaryAudioSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPatch.mockResolvedValue({});
    });

    it("uploads a picked audio file and saves its signed id with the by line", async () => {
        mockGetDocumentAsync.mockResolvedValue({ canceled: false, assets: [pickedAudio] });
        mockDirectUpload.mockResolvedValue("signed-audio-id");
        render(<SummaryAudioSection billId={42} bill={undefined} />);

        fireEvent.press(screen.getByTestId("admin-summary-audio-upload"));

        await waitFor(() =>
            expect(mockDirectUpload).toHaveBeenCalledWith({
                uri: "file:///cache/summary.mp3",
                filename: "summary.mp3",
                contentType: "audio/mpeg",
            }),
        );
        expect(mockGetDocumentAsync).toHaveBeenCalledWith({ type: "audio/*", copyToCacheDirectory: true });
        await waitFor(() =>
            expect(screen.getByTestId("admin-summary-audio-audio_bucket_path-input").props.value).toBe(
                "signed-audio-id",
            ),
        );
        typeInto("audio_by_line", "Sway Staff");

        fireEvent.press(screen.getByTestId("admin-summary-audio-save"));

        await waitFor(() => expect(mockApiPatch).toHaveBeenCalledTimes(1));
        expect(mockApiPatch).toHaveBeenCalledWith("/bills/42", {
            audio_bucket_path: "signed-audio-id",
            audio_by_line: "Sway Staff",
        });
        expect(await screen.findByText("Audio saved.")).toBeTruthy();
    });

    it("saves a pasted URL as the audio bucket path", async () => {
        render(<SummaryAudioSection billId={42} bill={{ audio_bucket_path: null, audio_by_line: "Old Line" }} />);

        typeInto("audio_bucket_path", "  https://example.com/summary.mp3 ");
        fireEvent.press(screen.getByTestId("admin-summary-audio-save"));

        await waitFor(() => expect(mockApiPatch).toHaveBeenCalledTimes(1));
        expect(mockApiPatch).toHaveBeenCalledWith("/bills/42", {
            audio_bucket_path: "https://example.com/summary.mp3",
            audio_by_line: "Old Line",
        });
        expect(mockDirectUpload).not.toHaveBeenCalled();
    });

    it("starts from the bill's saved audio and offers a new upload", () => {
        render(
            <SummaryAudioSection
                billId={42}
                bill={{ audio_bucket_path: "https://example.com/a.mp3", audio_by_line: "Sway Staff" }}
            />,
        );

        expect(screen.getByTestId("admin-summary-audio-audio_bucket_path-input").props.value).toBe(
            "https://example.com/a.mp3",
        );
        expect(screen.getByTestId("admin-summary-audio-audio_by_line-input").props.value).toBe("Sway Staff");
        expect(screen.getByText("Upload New Audio Summary")).toBeTruthy();
    });

    it("keeps Save disabled while a file uploads and enables it when the upload ends", async () => {
        mockGetDocumentAsync.mockResolvedValue({ canceled: false, assets: [pickedAudio] });
        let finishUpload: (signedId: string) => void = () => {};
        mockDirectUpload.mockReturnValue(
            new Promise<string>((resolve) => {
                finishUpload = resolve;
            }),
        );
        render(<SummaryAudioSection billId={42} bill={undefined} />);

        fireEvent.press(screen.getByTestId("admin-summary-audio-upload"));

        await waitFor(() => expect(screen.getByText("Uploading...")).toBeTruthy());
        expect(screen.getByTestId("admin-summary-audio-save").props.accessibilityState.disabled).toBe(true);
        fireEvent.press(screen.getByTestId("admin-summary-audio-save"));
        expect(mockApiPatch).not.toHaveBeenCalled();

        await act(async () => finishUpload("late-id"));

        expect(screen.getByTestId("admin-summary-audio-save").props.accessibilityState.disabled).toBeFalsy();
    });

    it("sends nothing when the file picker is closed", async () => {
        mockGetDocumentAsync.mockResolvedValue({ canceled: true, assets: null });
        render(<SummaryAudioSection billId={42} bill={undefined} />);

        fireEvent.press(screen.getByTestId("admin-summary-audio-upload"));

        await waitFor(() => expect(mockGetDocumentAsync).toHaveBeenCalled());
        expect(mockDirectUpload).not.toHaveBeenCalled();
    });

    it("shows a failed upload's message and leaves the path as it was", async () => {
        mockGetDocumentAsync.mockResolvedValue({ canceled: false, assets: [pickedAudio] });
        mockDirectUpload.mockRejectedValue(new Error("Uploading summary.mp3 failed (500)."));
        render(<SummaryAudioSection billId={42} bill={{ audio_bucket_path: "kept.mp3", audio_by_line: null }} />);

        fireEvent.press(screen.getByTestId("admin-summary-audio-upload"));

        expect(await screen.findByText("Uploading summary.mp3 failed (500).")).toBeTruthy();
        expect(screen.getByTestId("admin-summary-audio-audio_bucket_path-input").props.value).toBe("kept.mp3");
    });

    it("shows the server's message under the field it names", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError("validation_failed", "Validation failed.", { audio_by_line: ["is too long"] }, 422),
        );
        render(<SummaryAudioSection billId={42} bill={undefined} />);

        fireEvent.press(screen.getByTestId("admin-summary-audio-save"));

        expect(await screen.findByText("is too long")).toBeTruthy();
        expect(screen.queryByText("Audio saved.")).toBeNull();
    });

    it("asks to save the bill first when it has no id", () => {
        render(<SummaryAudioSection billId={null} bill={undefined} />);

        expect(screen.getByText("Save the bill before adding audio.")).toBeTruthy();
        expect(screen.queryByTestId("admin-summary-audio-save")).toBeNull();
    });
});
