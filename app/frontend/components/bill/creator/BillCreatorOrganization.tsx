import { getStoragePath } from "app/frontend/sway_utils";
import { getDownloadURL, ref, uploadBytes } from "firebase/storage";
import { useField } from "formik";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Form, Image } from "react-bootstrap";
import { sway } from "sway";
import { storage } from "../../../firebase";
import { useSwayFireClient } from "../../../hooks/useSwayFireClient";
import { handleError, notify } from "../../../sway_utils";
import { withEmojis } from "../../../sway_utils/emoji";
import { IDataOrganizationPosition } from "../../admin/types";
import SwayTextArea from "../../forms/SwayTextArea";
import SwaySpinner from "../../SwaySpinner";
import BillSummaryMarkdown from "../BillSummaryMarkdown";

interface IProps {
    index: number;
    organization: IDataOrganizationPosition;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void;
    error: string;
}

const BillCreatorOrganization: React.FC<IProps> = ({
    index,
    organization,
    setFieldValue,
    handleSetTouched,
    error,
}) => {
    const swayFireClient = useSwayFireClient();
    const fileUploadInputRef = useRef<HTMLInputElement | null>(null);
    const [isLoadingIcon, setLoadingIcon] = useState<boolean>(false);

    const [localeName] = useField("localeName");

    const [summary, setSummary] = useState<string>("");
    const handleChange = useCallback(async (_fieldname: string, fieldvalue: string) => {
        setSummary(withEmojis(fieldvalue));
    }, []);

    useEffect(() => {
        if (organization.iconPath) {
            fileUploadInputRef.current?.classList.add("invisible");
        }
    }, [organization.iconPath]);

    useEffect(() => {
        if (organization.position && !summary) {
            setSummary(organization.position);
        }
    }, [organization.position, summary]);

    useEffect(() => {
        setFieldValue(`organizations.${index}.position`, summary);
    }, [summary, setFieldValue, index]);

    const handleIconUpload = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            if (!organization.value) return;

            const files = e.target.files;
            if (!files) return;

            try {
                const file = files[0];
                if (!file) return;

                setLoadingIcon(true);

                const filename = `${organization.value
                    .replace(/[^\w\s]/gi, "")
                    .replace(/\s+/g, "-")
                    .toLowerCase()}.${file.name.split(".").last()}`;
                const filepath = `${localeName.value}/organizations/${filename}`;

                // https://firebase.google.com/docs/storage/web/upload-files
                const storageRef = ref(storage, filepath);

                // 'file' comes from the Blob or File API
                uploadBytes(storageRef, file, {
                    contentType: file.type,
                    customMetadata: {
                        name: filename,
                    },
                })
                    .then(() => {
                        notify({
                            level: "success",
                            title: `Uploaded icon ${filename}`,
                            message: `Path - ${filepath}`,
                        });
                        swayFireClient
                            .organizations()
                            .update({
                                name: organization.value,
                                iconPath: filename,
                            } as sway.IOrganization)
                            .then(() => {
                                setFieldValue(`organizations.${index}.iconPath`, filename);
                                setLoadingIcon(false);
                            })
                            .catch((err) => {
                                setLoadingIcon(false);
                                handleError(err);
                            });
                    })
                    .catch((ex) => {
                        setLoadingIcon(false);
                        handleError(ex);
                    });
            } catch (ex: any) {
                setLoadingIcon(false);
                console.error(ex);
            }
        },
        [localeName.value, organization.value, index, setFieldValue, swayFireClient],
    );

    const [swayIconBucketURL, setSwayIconBucketURL] = useState<string>("/thumbs-down.svg");
    useEffect(() => {
        if (organization?.iconPath && localeName.value) {
            const storageRef = ref(
                storage,
                getStoragePath(organization.iconPath, localeName.value, "organizations"),
            );
            getDownloadURL(storageRef).then(setSwayIconBucketURL).catch(console.error);
        }
    }, [localeName.value, organization?.iconPath, organization?.value, organization?.support]);

    const handleChangeSupport = useCallback(
        (event: React.ChangeEvent<HTMLInputElement>) => {
            const newSupport = event?.target.checked;
            setFieldValue(`organizations.${index}.support`, newSupport);
            if (!organization?.iconPath) {
                const icon = newSupport ? "/thumbs-up.svg" : "/thumbs-down.svg";
                setSwayIconBucketURL(icon);
            }
        },
        [setFieldValue, index, organization?.iconPath],
    );

    const renderAddOrganizationIcon = useMemo(() => {
        return (
            <Form.Group
                controlId={`organization-icon-upload-${organization.value}`}
                className="input-group custom-file-button mt-3 row align-items-center"
            >
                <div className="col-8">
                    <Form.Label className="input-group-text">
                        {organization.iconPath
                            ? `${organization.iconPath} - Click to change`
                            : `Select a file to be an icon for ${organization.value}`}
                        &nbsp;&nbsp;&nbsp;
                        <Form.Control
                            ref={fileUploadInputRef}
                            type="file"
                            onChange={handleIconUpload}
                        />
                    </Form.Label>
                </div>
                <div className="col-2">
                    {swayIconBucketURL && (
                        <Image
                            alt={organization.value}
                            style={{ width: "3em", height: "3em" }}
                            src={swayIconBucketURL}
                            className="m-auto"
                        />
                    )}
                </div>
                <div className="col-2">
                    <SwaySpinner isHidden={!isLoadingIcon} />
                </div>
            </Form.Group>
        );
    }, [
        handleIconUpload,
        isLoadingIcon,
        organization.iconPath,
        organization.value,
        swayIconBucketURL,
    ]);

    return (
        <div className="col py-2">
            <div className="row">
                <div className="col">
                    <Form.Check
                        type="switch"
                        checked={!!organization.support}
                        label={organization.support ? "Supports" : "Opposes"}
                        onChange={handleChangeSupport}
                    />
                </div>
            </div>
            <div className="row">
                <div className="col">
                    <SwayTextArea
                        field={{
                            name: `organizations.${index}.position`,
                            component: "textarea",
                            type: "text",
                            label: `${organization.value} Position Summary`,
                            isRequired: true,
                        }}
                        value={summary}
                        error={error}
                        setFieldValue={handleChange}
                        handleSetTouched={handleSetTouched}
                        helperText={`Why does ${organization.value} ${
                            organization.support ? "support" : "oppose"
                        } this bill?`}
                    />
                    {renderAddOrganizationIcon}
                </div>
                <div className="col">
                    <BillSummaryMarkdown summary={summary} />
                </div>
            </div>
        </div>
    );
};

export default BillCreatorOrganization;
