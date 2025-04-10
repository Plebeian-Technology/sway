import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import BillSummaryAudio from "app/frontend/components/bill/BillSummaryAudio";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { Suspense, lazy, useCallback, useState } from "react";
import { Button, Form, ProgressBar } from "react-bootstrap";
import { FiHeadphones } from "react-icons/fi";
import { sway } from "sway";

const FileUploadModal = lazy(() => import("app/frontend/components/dialogs/FileUploadModal"));

interface IProps {
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

const BillCreatorSummaryAudio: React.FC<IProps> = ({ onBlur }) => {
    const { data, setData } = useFormContext<IApiBillCreator>();

    const audio_by_line = data.audio_by_line ?? "";
    const audio_bucket_path = data.audio_bucket_path ?? "";

    const handleChangeSwayAudioByline = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            const value = e.target.value;
            setData("audio_by_line", value);
        },
        [setData],
    );

    const handleChangeSwayAudioBucketPath_URL = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            const value = e.target.value;
            setData("audio_bucket_path", value);
        },
        [setData],
    );

    const [showUploadModal, setShowUploadModal] = useState<boolean>(false);
    const handleShowHideUploadModal = useCallback(() => setShowUploadModal((current) => !current), []);

    const onAudioUpload = useCallback(
        (fileUpload: sway.files.IFileUpload) => {
            setData("audio_bucket_path", fileUpload.bucket_file_path);
            handleShowHideUploadModal();
        },
        [handleShowHideUploadModal, setData],
    );

    return (
        <div className="row my-3">
            <Form.Group className="col-xs-12 col-sm-6 mt-3" controlId={"audio_bucket_path"}>
                <div>
                    <Form.Label className="bold">Audio Bucket Path:</Form.Label>
                </div>
                {audio_bucket_path ? (
                    <>
                        <div className="w-100">
                            <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                                Upload New Audio Summary <FiHeadphones />
                            </Button>
                        </div>
                        <div className="bold my-2">OR</div>
                        <div>
                            <Form.Label>Use an external audio source:</Form.Label>
                            <Form.Control
                                type="text"
                                name={"audio_bucket_path"}
                                onChange={handleChangeSwayAudioBucketPath_URL}
                                value={audio_bucket_path}
                                placeholder="https://..."
                                onBlur={onBlur}
                            />
                        </div>
                        <div className="my-3">
                            <BillSummaryAudio audio_bucket_path={audio_bucket_path} audio_by_line={audio_by_line} />
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
                                name={"audio_bucket_path"}
                                onChange={handleChangeSwayAudioBucketPath_URL}
                                value={audio_bucket_path}
                                placeholder="https://..."
                                onBlur={onBlur}
                            />
                        </div>
                    </>
                )}
            </Form.Group>
            <Form.Group className="col-xs-12 col-sm-6 mt-3" controlId={"audio_by_line"}>
                <Form.Label className="bold">Audio By:</Form.Label>
                <Form.Control
                    type="text"
                    name={"audio_by_line"}
                    onChange={handleChangeSwayAudioByline}
                    value={audio_by_line}
                    onBlur={onBlur}
                />
            </Form.Group>
            <Suspense fallback={<ProgressBar />}>
                {showUploadModal && (
                    <FileUploadModal
                        fileName={data.external_id}
                        currentFilePath={audio_bucket_path || null}
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
