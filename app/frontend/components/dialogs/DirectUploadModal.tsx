import { DirectUpload } from "@rails/activestorage";
import { handleError } from "app/frontend/sway_utils";
import { ChangeEvent, useCallback, useMemo, useState } from "react";
import { Button, Form, Image, Modal, ProgressBar } from "react-bootstrap";

export interface IDirectUploadResult {
    signedId: string;
    previewUrl: string;
}

interface IProps {
    fileName: string;
    currentFilePath: string | null;
    accept: "image/*";
    onHide: () => void;
    callback?: (upload: IDirectUploadResult) => void;
}

const DIRECT_UPLOADS_PATH = "/rails/active_storage/direct_uploads";

const DirectUploadModal: React.FC<IProps> = ({ fileName, currentFilePath, accept, onHide, callback }) => {
    const [file, setFile] = useState<File | undefined>();
    const [progress, setProgress] = useState<number>(0);
    const [previewUrl, setPreviewUrl] = useState<string>("");

    const filePath = useMemo(() => previewUrl || currentFilePath, [previewUrl, currentFilePath]);

    const onSubmit = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            e.stopPropagation();

            if (!file) return;

            const upload = new DirectUpload(file, DIRECT_UPLOADS_PATH, {
                directUploadWillStoreFileWithXHR: (xhr) => {
                    xhr.upload.addEventListener("progress", (event: ProgressEvent<EventTarget>) => {
                        if (!event.lengthComputable || event.total === 0) {
                            return;
                        }

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

                const localPreviewUrl = URL.createObjectURL(file);
                setPreviewUrl(localPreviewUrl);
                setFile(undefined);
                callback?.({ signedId: blob.signed_id, previewUrl: localPreviewUrl });
                setProgress(0);
            });
        },
        [callback, file],
    );

    const onFile = useCallback((e: ChangeEvent<HTMLInputElement>) => {
        if (e.target.files) {
            setFile(e.target.files[0]);
        }
    }, []);

    return (
        <Modal show={!!fileName} onHide={onHide} size="lg">
            <Modal.Header>
                <Modal.Title>Upload image</Modal.Title>
            </Modal.Header>
            <Modal.Body>
                <div className="col">
                    <div>
                        <Form.Control type="file" onChange={onFile} accept={accept} />
                        {filePath && (
                            <span>
                                <span className="bold">Current File: </span>
                                <span>{filePath}</span>
                            </span>
                        )}
                    </div>
                    <div>
                        {filePath ? (
                            <Image alt={fileName} style={{ maxWidth: 300 }} src={filePath} className="m-auto" />
                        ) : (
                            <ProgressBar
                                className={`w-100 ${progress === 0 ? "invisible" : ""}`}
                                now={progress}
                                label={`${progress.toFixed(1)}%`}
                            />
                        )}
                    </div>
                </div>
            </Modal.Body>
            <Modal.Footer>
                <Button variant="secondary" onClick={onHide} disabled={!!progress}>
                    Close
                </Button>
                <Button variant="primary" onClick={onSubmit} disabled={!!progress || !file}>
                    {!!progress ? "Uploading..." : progress >= 100 ? "Done" : "Upload"}
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default DirectUploadModal;
