import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { logDev } from "@sway/utils";
import { ref, uploadBytes } from "firebase/storage";
import { useField } from "formik";
import { useState } from "react";
import { Form } from "react-bootstrap";
import { storage } from "../../firebase";
import { handleError, notify } from "../../utils";
import SwaySpinner from "../SwaySpinner";

interface IProps {
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
}

const BillCreatorSummaryAudio: React.FC<IProps> = ({ setFieldValue }) => {
    const [audio] = useField("swayAudioBucketPath");
    const [audioByline] = useField("audioByline");
    const [localeName] = useField("localeName");
    const [externalId] = useField("externalId");
    const [externalVersion] = useField("externalVersion");
    const [isLoading, setLoading] = useState<boolean>(false);

    const getFirestoreId = () => {
        if (externalId.value && externalVersion.value) {
            return `${externalId.value}v${externalVersion.value}`;
        } else {
            return externalId.value;
        }
    };

    const billFirestoreId = getFirestoreId();

    logDev("BillCreatorSummaryAudio -", {
        audio: audio.value,
        localeName: localeName.value,
        billFirestoreId: billFirestoreId,
    });

    const handleAudioUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        if (!billFirestoreId || !localeName.value) {
            notify({
                level: "warning",
                title: "A bill id and/or locale is required before uploading an audio file.",
            });
            return;
        }

        e.preventDefault();
        const files = e.target.files;
        if (!files) return;

        setLoading(true);

        try {
            const file = files[0];
            const filename = `sway-summary-${billFirestoreId}.${file.name.split(".").last()}`;
            const filepath = `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName.value}%2Faudio%2F${filename}?alt=media`;

            logDev("UPLOADING AUDIO", {
                file,
                filename,
                filepath,
                filetype: file.type,
            });

            // https://firebase.google.com/docs/storage/web/upload-files
            const storageRef = ref(storage, filepath);

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
                        message: `Path - ${filepath}`,
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
                            {audio.value
                                ? audio.value
                                      .split("/")
                                      .last()
                                      .split("%2F")
                                      .last()
                                      .split("?")
                                      .first()
                                : `Audio File ${billFirestoreId}`}
                        </Form.Label>
                    </div>
                    <div className="col-3 text-end">
                        <SwaySpinner isHidden={!isLoading} small />
                    </div>
                </div>
                <Form.Control
                    type="file"
                    className="mb-3"
                    disabled={isLoading}
                    onChange={handleAudioUpload}
                />
                {audio.value && <audio controls={true} src={audio.value} itemType={"audio/mpeg"} />}
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
                    onChange={audioByline.onChange}
                />
            </Form.Group>
        </div>
    );
};

export default BillCreatorSummaryAudio;
