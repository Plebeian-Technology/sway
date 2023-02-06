import { getStoragePath, logDev } from "@sway/utils";
import { getDownloadURL, ref, uploadBytes } from "firebase/storage";
import { useField } from "formik";
import { useCallback, useEffect, useRef, useState } from "react";
import { Form } from "react-bootstrap";
import { storage } from "../../firebase";
import { handleError, notify } from "../../utils";
import SwaySpinner from "../SwaySpinner";

interface IProps {
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
}

const BillCreatorSummaryAudio: React.FC<IProps> = ({ setFieldValue }) => {
    const fileRef = useRef<HTMLInputElement | null>(null);

    const [swayAudioBucketPath] = useField("swayAudioBucketPath");
    const [swayAudioByline] = useField("swayAudioByline");
    const [localeName] = useField("localeName");
    const [externalId] = useField("externalId");
    const [externalVersion] = useField("externalVersion");
    const [summaries] = useField("summaries");
    const [isLoading, setLoading] = useState<boolean>(false);

    const getFirestoreId = () => {
        if (externalId.value && externalVersion.value) {
            return `${externalId.value}v${externalVersion.value}`;
        } else {
            return externalId.value;
        }
    };

    const billFirestoreId = getFirestoreId();

    const byline = swayAudioByline.value || summaries?.value?.swayAudioByline || "";
    const audioPath = swayAudioBucketPath.value || summaries?.value?.swayAudioBucketPath || "";

    const [swayAudioBucketURL, setSwayAudioBucketURL] = useState<string | undefined>();

    // logDev("BillCreatorSummaryAudio -", {
    //     audioPath,
    //     byline,
    //     swayAudioBucketPath: swayAudioBucketPath.value,
    //     swayAudioByline: swayAudioByline.value,
    //     swayAudioBucketURL,
    //     localeName: localeName.value,
    //     billFirestoreId: billFirestoreId,
    // });

    useEffect(() => {
        function loadURLToInputFiled() {
            const storageRef = ref(storage, audioPath);
            getDownloadURL(storageRef)
                .then((url) => {
                    setFieldValue("swayAudioBucketPath", audioPath);
                    setSwayAudioBucketURL(url);

                    if (url && fileRef.current) {
                        fetch(url)
                            .then((res) => res.blob())
                            .then((blob) => {
                                /**
                                 *
                                 * Set default value on file input
                                 * https://stackoverflow.com/a/47172409/6410635
                                 *
                                 */
                                const container = new DataTransfer();
                                container.items.add(
                                    new File([blob], audioPath, {
                                        type: "audio/mpeg",
                                        lastModified: new Date().getTime(),
                                    }),
                                );
                                if (fileRef.current) {
                                    fileRef.current.files = container.files;
                                }
                            })
                            .catch(handleError);
                    }
                })
                .catch(handleError);
        }
        if (audioPath) {
            loadURLToInputFiled();
        }
    }, [audioPath, setFieldValue]);

    const handleChangeSwayAudioByline = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            const value = e.target.value;
            setFieldValue("swayAudioByline", value);
        },
        [setFieldValue],
    );

    const handleAudioUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        e.preventDefault();
        e.stopPropagation();

        if (!billFirestoreId || !localeName.value) {
            notify({
                level: "warning",
                title: "A bill id and/or locale is required before uploading an audio file.",
            });
            return;
        }

        const files = e.target.files;
        if (!files) return;

        try {
            const file = files[0];
            if (!file) return;

            setLoading(true);

            const filename = `sway-summary-${billFirestoreId}.${file.name.split(".").last()}`;
            const fileSuffix = getStoragePath(filename, localeName.value, "audio");
            const filepath = fileSuffix;

            // https://firebase.google.com/docs/storage/web/upload-files
            const storageRef = ref(storage, filepath);

            logDev("UPLOADING AUDIO", {
                file,
                filename,
                filepath,
                filetype: file.type,
            });

            // 'file' comes from the Blob or File API
            await uploadBytes(storageRef, file, {
                contentType: file.type,
                customMetadata: {
                    name: filename,
                },
            })
                .then(() => {
                    setLoading(false);
                    notify({
                        level: "success",
                        title: `Uploaded audio ${filename}`,
                        message: `Path - ${fileSuffix}`,
                    });
                    setFieldValue("swayAudioBucketPath", filepath);
                })
                .catch((ex) => {
                    setLoading(false);
                    handleError(ex);
                });
        } catch (ex: any) {
            setLoading(false);
            console.error(ex);
        }
    };

    return (
        <div className="row my-3">
            <Form.Group controlId={`sway-audio-summary-${billFirestoreId}`} className="col">
                <div className="row align-items-center pb-1">
                    <div className="col-9">
                        <Form.Label className="bold">
                            {audioPath
                                ? audioPath.split("/").last().split("%2F").last().split("?").first()
                                : `Audio File ${billFirestoreId}`}
                        </Form.Label>
                    </div>
                    <div className="col-3 text-end">
                        <SwaySpinner isHidden={!isLoading} small />
                    </div>
                </div>
                <Form.Control
                    ref={fileRef}
                    type="file"
                    className="mb-3"
                    disabled={isLoading}
                    onChange={handleAudioUpload}
                />
                {swayAudioBucketURL && (
                    <audio controls={true} src={swayAudioBucketURL} itemType={"audio/mpeg"} />
                )}
            </Form.Group>
            <Form.Group controlId={`sway-summary-audio-byline-${billFirestoreId}`} className="col">
                <div className="row align-items-center pb-1">
                    <div className="col-9">
                        <Form.Label className="bold">Audio By:</Form.Label>
                    </div>
                    <div className="col-3 text-end">
                        <SwaySpinner isHidden={!isLoading} small />
                    </div>
                </div>
                <Form.Control
                    type="text"
                    disabled={isLoading}
                    name={"swayAudioByline"}
                    onChange={handleChangeSwayAudioByline}
                    value={byline}
                />
            </Form.Group>
        </div>
    );
};

export default BillCreatorSummaryAudio;
