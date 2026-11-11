// @lat: [[direct-upload-dialog-object-url-cleanup#Why DirectUploadDialog wraps DirectUpload instead of being duplicated]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// This fake DirectUpload hands back a blob right away, with no waiting.
vi.mock("@rails/activestorage", () => ({
    DirectUpload: class {
        create(cb: (err: unknown, blob: { signed_id: string }) => void) {
            cb(null, { signed_id: "sig" });
        }
    },
}));

// A stripped-down Dialog with a real close button. Clicking it calls
// onOpenChange(false), which is what makes the component run its reset().
vi.mock("app/frontend/components/ui/dialog", () => ({
    Dialog: ({ open, onOpenChange, children }: any) =>
        open ? (
            <div>
                <button
                    type="button"
                    data-testid="dialog-close"
                    aria-label="Close"
                    onClick={() => onOpenChange(false)}
                />
                {children}
            </div>
        ) : null,
    DialogContent: ({ children }: any) => <div>{children}</div>,
    DialogHeader: ({ children }: any) => <div>{children}</div>,
    DialogTitle: ({ children }: any) => <div>{children}</div>,
    DialogDescription: ({ children }: any) => <div>{children}</div>,
    DialogFooter: ({ children }: any) => <div>{children}</div>,
}));

import DirectUploadDialog from "app/frontend/components/admin/creator/DirectUploadDialog";

let urlCounter = 0;
let createObjectURLMock: ReturnType<typeof vi.fn>;
let revokeObjectURLMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
    urlCounter = 0;
    createObjectURLMock = vi.fn<(blob: Blob) => string>(() => `blob:${++urlCounter}`);
    revokeObjectURLMock = vi.fn<(url: string) => void>();
    (URL as unknown as Record<string, unknown>).createObjectURL = createObjectURLMock;
    (URL as unknown as Record<string, unknown>).revokeObjectURL = revokeObjectURLMock;
});
afterEach(() => cleanup());

const uploadOnce = (container: HTMLElement) => {
    const input = container.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(["x"], "a.mp3", { type: "audio/mpeg" });
    fireEvent.change(input, { target: { files: [file] } });
    fireEvent.click(screen.getByRole("button", { name: "Upload" }));
};

describe("DirectUploadDialog — object URL cleanup", () => {
    it("revokes a superseded preview URL on a second upload in the same session without revoking the final preview URL on dialog close", () => {
        const onUploaded = vi.fn<(result: { signedId: string; previewUrl: string }) => void>();
        const { container } = render(
            <DirectUploadDialog
                open
                onOpenChange={vi.fn<(open: boolean) => void>()}
                accept="audio/*"
                onUploaded={onUploaded}
            />,
        );

        uploadOnce(container); // blob:1
        expect(onUploaded).toHaveBeenCalledWith({ signedId: "sig", previewUrl: "blob:1" });
        expect(revokeObjectURLMock).not.toHaveBeenCalled();

        uploadOnce(container); // revokes blob:1, creates blob:2
        expect(revokeObjectURLMock).toHaveBeenCalledWith("blob:1");
        expect(onUploaded).toHaveBeenCalledWith({ signedId: "sig", previewUrl: "blob:2" });

        fireEvent.click(screen.getByTestId("dialog-close")); // reset must not revoke parent's active blob:2
        expect(revokeObjectURLMock).not.toHaveBeenCalledWith("blob:2");
    });
});
