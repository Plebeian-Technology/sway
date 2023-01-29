import { logDev } from "@sway/utils";
import { getDownloadURL, ref, uploadBytes } from "firebase/storage";
import { useField } from "formik";
import React, { useCallback, useEffect, useRef, useState } from "react";
import { Form, Image } from "react-bootstrap";
import { sway } from "sway";
import { storage } from "../../../firebase";
import { useSwayFireClient } from "../../../hooks/useSwayFireClient";
import { handleError, notify } from "../../../utils";
import { withEmojis } from "../../../utils/emoji";
import { IDataOrganizationPosition } from "../../admin/types";
import SwayTextArea from "../../forms/SwayTextArea";
import SwaySpinner from "../../SwaySpinner";
import BillSummaryMarkdown from "../BillSummaryMarkdown";

interface IProps {
    fieldname: string;
    organization: IDataOrganizationPosition;
    isSupporting: boolean;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void;
    error: string;
}

const BillCreatorOrganization: React.FC<IProps> = ({
    fieldname,
    organization,
    setFieldValue,
    handleSetTouched,
    isSupporting,
    error,
}) => {
    const swayFireClient = useSwayFireClient();
    const fileUploadInputRef = useRef<HTMLInputElement | null>(null);
    const [org, setOrg] = useState<IDataOrganizationPosition>(organization);
    const [isLoadingIcon, setLoadingIcon] = useState<boolean>(false);

    const organizationName = organization.value;
    const positionFieldname = `${fieldname}.position`;
    const supportsFieldname = `${fieldname}.support`;

    const [localeName] = useField("localeName");
    const [organizations] = useField("organizations");
    const [formikPosition] = useField(positionFieldname);

    const [summary, setSummary] = useState<string>("");
    const handleChange = useCallback(async (_fieldname: string, fieldvalue: string) => {
        setSummary(withEmojis(fieldvalue));
    }, []);

    useEffect(() => {
        if (org.iconPath) {
            fileUploadInputRef.current?.classList.add("invisible");
        }
    }, [org.iconPath]);

    useEffect(() => {
        logDev("BillCreatorOrganization.useEffect - LOAD");
        const load = async () => {
            if (formikPosition.value && !summary) {
                logDev("BILL CREATOR - ORGANIZATION LOAD");
                setSummary(formikPosition.value);
            }
        };
        load().catch(handleError);
    }, []);

    useEffect(() => {
        logDev("BillCreatorOrganization.useEffect - SEND VALUE");
        const sendValue = async () => {
            setFieldValue(positionFieldname, summary);
            handleSetTouched(positionFieldname);
        };
        sendValue().catch(handleError);
    }, [summary]);

    const handleIconUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
        e.preventDefault();
        e.stopPropagation();

        const files = e.target.files;
        if (!files) return;

        try {
            const file = files[0];
            if (!file) return;

            setLoadingIcon(true);

            const filename = `${organizationName}.${file.name.split(".").last()}`;
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
                    setOrg((current) => ({ ...current, iconPath: filename }));
                    setFieldValue(
                        "organizations",
                        organizations.value.map((o: sway.IOrganization) => {
                            if (o.name === organizationName) {
                                return {
                                    ...o,
                                    iconPath: filename,
                                };
                            } else {
                                return o;
                            }
                        }),
                    );
                    swayFireClient
                        .organizations()
                        .update({
                            name: organizationName,
                            iconPath: filename,
                        } as sway.IOrganization)
                        .then(() => {
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
    };

    const [swayIconBucketURL, setSwayIconBucketURL] = useState<string | undefined>();
    useEffect(() => {
        const isSway = org?.value?.toLowerCase() === "sway";
        const defaultSupportIcon = org?.support ? "/thumbs-up.svg" : "/thumbs-down.svg";
        const defaultValue = (() => {
            if (!org) {
                return "/sway-us-light.png";
            }
            if (isSway) {
                return "/sway-us-light.png";
            }
            if (!org.iconPath || !localeName) {
                return defaultSupportIcon;
            }
        })();

        function loadURLToInputFiled() {
            const storageRef = ref(
                storage,
                `${localeName}/organizations/${org?.iconPath}?alt=media`,
            );
            getDownloadURL(storageRef).then(setSwayIconBucketURL).catch(console.error);
        }
        if (org?.iconPath && org?.value && !isSway) {
            loadURLToInputFiled();
        } else {
            setSwayIconBucketURL(defaultValue);
        }
    }, [localeName, org?.iconPath, org?.value, org?.support]);

    const renderAddOrganizationIcon = () => {
        return (
            <Form.Group
                controlId={`organization-icon-upload-${organizationName}`}
                className="input-group custom-file-button mt-3 row align-items-center"
            >
                <div className="col-8">
                    <Form.Label className="input-group-text">
                        {org.iconPath
                            ? `${org.iconPath} - Click to change`
                            : `Select a file to be an icon for ${organizationName}`}
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
                            alt={organizationName}
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
    };

    return (
        <div className="col py-2">
            <div className="row">
                <div className="col">
                    <Form.Check
                        type="switch"
                        checked={isSupporting}
                        label={isSupporting ? "Supports" : "Opposes"}
                        onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                            setFieldValue(supportsFieldname, event?.target.checked);
                            handleSetTouched(supportsFieldname);
                        }}
                    />
                </div>
            </div>
            <div className="row">
                <div className="col">
                    <SwayTextArea
                        field={{
                            name: positionFieldname,
                            component: "textarea",
                            type: "text",
                            label: `${organizationName} Position Summary`,
                            isRequired: true,
                        }}
                        value={summary}
                        error={error}
                        setFieldValue={handleChange}
                        handleSetTouched={handleSetTouched}
                        helperText={`Why does ${organizationName} ${
                            isSupporting ? "support" : "oppose"
                        } this bill?`}
                    />
                    {renderAddOrganizationIcon()}
                </div>
                <div className="col">
                    <BillSummaryMarkdown summary={summary} />
                </div>
            </div>
        </div>
    );
};

export default BillCreatorOrganization;
