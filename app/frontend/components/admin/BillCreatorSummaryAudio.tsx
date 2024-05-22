import BillSummaryAudio from "app/frontend/components/bill/BillSummaryAudio";
import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import { useField } from "formik";
import { Suspense, lazy, useCallback, useState } from "react";
import { Button, Form } from "react-bootstrap";
import { FiHeadphones } from "react-icons/fi";
import { sway } from "sway";

const FileUploadModal = lazy(() => import("app/frontend/components/dialogs/FileUploadModal"));

interface IProps {
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
}

const BillCreatorSummaryAudio: React.FC<IProps> = ({ setFieldValue }) => {
    const [externalIdField] = useField("externalId");
    const [audioBucketPathField] = useField("audioBucketPath");
    const [audioByLineField] = useField("audioByLine");

    const audioByLine = audioByLineField.value;
    const audioBucketPath = audioBucketPathField.value;

    const handleChangeSwayAudioByline = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            const value = e.target.value;
            setFieldValue("audioByLine", value);
        },
        [setFieldValue],
    );

    const handleChangeSwayAudioBucketPath_URL = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            const value = e.target.value;
            setFieldValue("audioBucketPath", value);
        },
        [setFieldValue],
    );

    const [showUploadModal, setShowUploadModal] = useState<boolean>(false);
    const handleShowHideUploadModal = useCallback(() => setShowUploadModal((current) => !current), []);

    const onAudioUpload = useCallback(
        (fileUpload: sway.files.IFileUpload) => {
            setFieldValue("audioBucketPath", fileUpload.bucketFilePath);
            handleShowHideUploadModal();
        },
        [handleShowHideUploadModal, setFieldValue],
    );

    return (
        <div className="row my-3">
            <Form.Group className="col" controlId={"audioBucketPath"}>
                <div>
                    <Form.Label className="bold">Audio Bucket Path:</Form.Label>
                </div>
                {audioBucketPath ? (
                    <>
                        <div>
                            <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                                Upload New Audio Summary <FiHeadphones />
                            </Button>
                        </div>
                        <div className="bold my-2">OR</div>
                        <div>
                            <Form.Label>Use an external audio source:</Form.Label>
                            <Form.Control
                                type="text"
                                name={"audioBucketPath"}
                                onChange={handleChangeSwayAudioBucketPath_URL}
                                value={audioBucketPath}
                            />
                        </div>
                        <div className="my-3">
                            <BillSummaryAudio audioBucketPath={audioBucketPath} audioByLine={audioByLine} />
                        </div>
                    </>
                ) : (
                    <>
                        <div>
                            <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                                Upload Audio Summary <FiHeadphones />
                            </Button>
                        </div>
                        <div className="bold my-2">OR</div>
                        <div>
                            <Form.Label>Use an external audio source:</Form.Label>
                            <Form.Control
                                type="text"
                                name={"audioBucketPath"}
                                onChange={handleChangeSwayAudioBucketPath_URL}
                                value={audioBucketPath}
                            />
                        </div>
                    </>
                )}
            </Form.Group>
            <Form.Group className="col" controlId={"audioByLine"}>
                <Form.Label className="bold">Audio By:</Form.Label>
                <Form.Control
                    type="text"
                    name={"audioByLine"}
                    onChange={handleChangeSwayAudioByline}
                    value={audioByLine}
                />
            </Form.Group>
            <Suspense fallback={<FullScreenLoading />}>
                {showUploadModal && (
                    <FileUploadModal
                        fileName={externalIdField.value}
                        currentFilePath={audioBucketPath || null}
                        onHide={handleShowHideUploadModal}
                        callback={onAudioUpload}
                        accept="audio/*"
                    />
                )}
            </Suspense>
        </div>
    );
};

export default BillCreatorSummaryAudio;
