import SwayAudio from "app/frontend/components/SwayAudio";
import { usePresignedBucketUpload } from "app/frontend/hooks/buckets/usePresignedBucketUpload";
import { usePresignedBucketUploadUrl } from "app/frontend/hooks/buckets/usePresignedBucketUploadUrl";
import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";
import { handleError } from "app/frontend/sway_utils";
import { ChangeEvent, useCallback, useMemo, useState } from "react";
import { Button, Form, Image, Modal, ProgressBar } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    fileName: string;
    currentFilePath: string | null;
    accept: "audio/*" | "image/*" | "video/*"; // https://html.spec.whatwg.org/multipage/input.html#attr-input-accept
    onHide: () => void;
    callback?: (fileUpload: sway.files.IFileUpload) => void;
}

const FileUploadModal: React.FC<IProps> = ({ fileName, currentFilePath, accept, onHide, callback }) => {
    const [file, setFile] = useState<File | undefined>();
    const [progress, setProgress] = useState<number>(0);

    const { post: createPresignedFileUpload } = usePresignedBucketUploadUrl();
    const upload = usePresignedBucketUpload();

    const [newFilePath, setNewFilePath] = useState<string>("");
    const filePath = useMemo(() => newFilePath || currentFilePath, [newFilePath, currentFilePath]);

    const onSubmit = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            e.stopPropagation();

            if (!file) return;

            const cacheBust = new Date().valueOf();
            const name = `${fileName}-${cacheBust}.${file.name.split(".").last()}`;

            createPresignedFileUpload({ name, mime_type: file.type })
                .then((fileUpload) => {
                    if (!fileUpload) return;

                    upload(file, fileUpload.bucketFilePath, fileUpload.url, {
                        onProgress: (_bucketFilePath, _fileName, uploadProgress) => {
                            setProgress(uploadProgress);
                        },
                        onDone: (fu) => {
                            setFile(undefined);
                            setProgress(0);
                            setNewFilePath(fileUpload.bucketFilePath);
                            callback?.(fu);
                        },
                    }).catch(handleError);
                })
                .catch(handleError);
        },
        [callback, createPresignedFileUpload, file, fileName, upload],
    );

    const onFile = useCallback((e: ChangeEvent<HTMLInputElement>) => {
        if (e.target.files) {
            setFile(e.target.files[0]);
        }
    }, []);

    return (
        <Modal show={!!fileName} onHide={onHide} size="lg">
            <Modal.Header>
                <Modal.Title>Upload file to GCP Bucket</Modal.Title>
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
                            accept === "audio/*" ? (
                                <SwayAudio filePath={filePath} />
                            ) : (
                                <Image
                                    alt={fileName}
                                    style={{ maxWidth: 300 }}
                                    src={`${SWAY_ASSETS_BUCKET_BASE_URL}/${filePath}`}
                                    className="m-auto"
                                />
                            )
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
                <Button variant="secondary" onClick={onHide}>
                    Close
                </Button>
                <Button variant="primary" onClick={onSubmit}>
                    Upload
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default FileUploadModal;
