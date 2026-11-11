import { DirectUpload } from "@rails/activestorage";
import { handleError } from "app/frontend/sway_utils";
import { ChangeEvent, useCallback, useMemo, useRef, useState } from "react";
import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Input } from "app/frontend/components/ui/input";
import { Progress } from "app/frontend/components/ui/progress";

export interface IDirectUploadResult {
    signedId: string;
    previewUrl: string;
}

interface IProps {
    open: boolean;
    onOpenChange: (next: boolean) => void;
    fileName?: string;
    currentFilePath?: string | null;
    accept: string;
    title?: string;
    onUploaded: (result: IDirectUploadResult) => void;
}

// @lat: [[direct-upload-dialog-object-url-cleanup#Why DirectUploadDialog wraps DirectUpload instead of being duplicated]]
const DIRECT_UPLOADS_PATH = "/rails/active_storage/direct_uploads";

const DirectUploadDialog: React.FC<IProps> = ({
    open,
    onOpenChange,
    fileName,
    currentFilePath,
    accept,
    title = "Upload file",
    onUploaded,
}) => {
    const [file, setFile] = useState<File | undefined>();
    const [progress, setProgress] = useState<number>(0);
    const [previewUrl, setPreviewUrl] = useState<string>("");
    // @lat: [[direct-upload-dialog-object-url-cleanup#Why previewUrlRef mirrors previewUrl state]]
    const previewUrlRef = useRef<string | null>(null);

    const filePath = useMemo(() => previewUrl || currentFilePath || "", [previewUrl, currentFilePath]);

    const reset = useCallback(() => {
        previewUrlRef.current = null;
        setFile(undefined);
        setPreviewUrl("");
        setProgress(0);
    }, []);

    const onFile = useCallback((e: ChangeEvent<HTMLInputElement>) => {
        if (e.target.files && e.target.files[0]) {
            setFile(e.target.files[0]);
        }
    }, []);

    const onSubmit = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            e.stopPropagation();
            if (!file) return;

            const upload = new DirectUpload(file, DIRECT_UPLOADS_PATH, {
                directUploadWillStoreFileWithXHR: (xhr) => {
                    xhr.upload.addEventListener("progress", (event: ProgressEvent<EventTarget>) => {
                        if (!event.lengthComputable || event.total === 0) return;
                        setProgress((event.loaded / event.total) * 100);
                    });
                },
            });

            upload.create((error: string | Error | null, blob: { signed_id: string } | null) => {
                if (error || !blob) {
                    handleError(
                        typeof error === "string" ? new Error(error) : (error ?? new Error("Direct upload failed")),
                    );
                    setProgress(0);
                    return;
                }

                // @lat: [[direct-upload-dialog-object-url-cleanup#Why the previous preview is released before the new one is created]]
                if (previewUrlRef.current) {
                    URL.revokeObjectURL(previewUrlRef.current);
                }
                const localPreviewUrl = URL.createObjectURL(file);
                previewUrlRef.current = localPreviewUrl;
                setPreviewUrl(localPreviewUrl);
                setFile(undefined);
                onUploaded({ signedId: blob.signed_id, previewUrl: localPreviewUrl });
                setProgress(0);
            });
        },
        [file, onUploaded],
    );

    const busy = progress > 0 && progress < 100;

    return (
        <Dialog
            open={open}
            onOpenChange={(next) => {
                if (!next) reset();
                onOpenChange(next);
            }}
        >
            <DialogContent className="inset-0 top-0 left-0 h-full max-h-none w-full max-w-none translate-x-0 translate-y-0 overflow-y-auto rounded-none border-0 p-4 sm:inset-auto sm:top-[50%] sm:left-[50%] sm:h-auto sm:max-h-[90dvh] sm:max-w-xl sm:translate-x-[-50%] sm:translate-y-[-50%] sm:rounded-xl sm:border-neo sm:p-6">
                <DialogHeader>
                    <DialogTitle>{title}</DialogTitle>
                    {fileName && <DialogDescription>For bill: {fileName}</DialogDescription>}
                </DialogHeader>

                <div className="flex flex-col gap-3">
                    <Input type="file" onChange={onFile} accept={accept} disabled={busy} className="min-h-[44px]" />
                    {filePath && (
                        <p className="text-xs text-muted-foreground break-all">
                            <span className="font-semibold">Current file:</span> <span>{filePath}</span>
                        </p>
                    )}
                    {busy && (
                        <div className="flex flex-col gap-1">
                            <Progress value={progress} />
                            <p className="text-xs tabular-nums lining-nums text-muted-foreground">
                                {progress.toFixed(1)}%
                            </p>
                        </div>
                    )}
                </div>

                <DialogFooter className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                    <Button
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                        disabled={busy}
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                    >
                        Close
                    </Button>
                    <Button
                        onClick={onSubmit}
                        disabled={busy || !file}
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                    >
                        {busy ? "Uploading..." : "Upload"}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default DirectUploadDialog;
