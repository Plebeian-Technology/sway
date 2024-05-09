import { useField, useFormikContext } from "formik";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Form, Image } from "react-bootstrap";
import { sway } from "sway";

import { withEmojis } from "../../../sway_utils/emoji";
import SwaySpinner from "../../SwaySpinner";
import SwayTextArea from "../../forms/SwayTextArea";
import BillSummaryMarkdown from "../BillSummaryMarkdown";
import { logDev } from "app/frontend/sway_utils";

interface IProps {
    swayFieldName: string;
    organization: sway.IOrganizationBase;
    handleSetTouched: (fieldname: string) => void;
    error: string;
}

const BillCreatorOrganization: React.FC<IProps> = ({ swayFieldName, organization, handleSetTouched, error }) => {
    const { setFieldValue } = useFormikContext();
    const [formikField] = useField(swayFieldName)

    const fileUploadInputRef = useRef<HTMLInputElement | null>(null);
    const [isLoadingIcon, setLoadingIcon] = useState<boolean>(false);

    const [swayIconBucketURL, setSwayIconBucketURL] = useState<string>(swayFieldName.toLowerCase().includes("oppose") ? "/images/thumbs-down.svg" : "/images/thumbs-up.svg");
    const handleChange = useCallback(async (_fieldname: string, fieldvalue: string) => {
        setSummary(withEmojis(fieldvalue));
    }, []);
    
    useEffect(() => {
        if (organization.iconPath) {
            fileUploadInputRef.current?.classList.add("invisible");
        }
    }, [organization.iconPath]);
    
    // Async updating of formik field using a useEffect and local summary state
    const [summary, setSummary] = useState<string>(formikField?.value?.summary ?? "");
    useEffect(() => {
        setFieldValue(`${swayFieldName}.summary`, summary).catch(console.error);
    }, [summary, setFieldValue, swayFieldName]);

    const handleIconUpload = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            e.preventDefault();
            e.stopPropagation();

            if (!organization.id) return;

            const files = e.target.files;
            if (!files) return;

            // try {
            //     const file = files[0];
            //     if (!file) return;

            //     setLoadingIcon(true);

            //     const filename = `${organization.value
            //         .replace(/[^\w\s]/gi, "")
            //         .replace(/\s+/g, "-")
            //         .toLowerCase()}.${file.name.split(".").last()}`;
            //     const filepath = `${localeName.value}/organizations/${filename}`;

            // https://firebase.google.com/docs/storage/web/upload-files
            // const storageRef = ref(storage, filepath);

            // 'file' comes from the Blob or File API
            //     uploadBytes(storageRef, file, {
            //         contentType: file.type,
            //         customMetadata: {
            //             name: filename,
            //         },
            //     })
            //         .then(() => {
            //             notify({
            //                 level: "success",
            //                 title: `Uploaded icon ${filename}`,
            //                 message: `Path - ${filepath}`,
            //             });
            //             swayFireClient
            //                 .organizations()
            //                 .update({
            //                     name: organization.value,
            //                     iconPath: filename,
            //                 } as sway.IOrganization)
            //                 .then(() => {
            //                     setFieldValue(`organizations.${index}.iconPath`, filename);
            //                     setLoadingIcon(false);
            //                 })
            //                 .catch((err) => {
            //                     setLoadingIcon(false);
            //                     handleError(err);
            //                 });
            //         })
            //         .catch((ex) => {
            //             setLoadingIcon(false);
            //             handleError(ex);
            //         });
            // } catch (ex: any) {
            //     setLoadingIcon(false);
            //     console.error(ex);
            // }
        },
        [organization.id],
    );

    // useEffect(() => {
        // if (organization?.iconPath && localeName.value) {
        //     const storageRef = ref(
        //         storage,
        //         getStoragePath(organization.iconPath, localeName.value, "organizations"),
        //     );
        //     getDownloadURL(storageRef).then(setSwayIconBucketURL).catch(console.error);
        // }
    // }, [localeName.value, organization?.iconPath, organization?.value, organization?.support]);

    const renderAddOrganizationIcon = useMemo(() => {
        return (
            <Form.Group
                controlId={`organization-icon-upload-${organization.id}`}
                className="input-group custom-file-button mt-3 row align-items-center"
            >
                <div className="col-8">
                    <Form.Label className="input-group-text">
                        {organization.iconPath
                            ? `${organization.iconPath} - Click to change`
                            : `Select a file to be an icon for ${organization.name}`}
                        &nbsp;&nbsp;&nbsp;
                        <Form.Control ref={fileUploadInputRef} type="file" onChange={handleIconUpload} />
                    </Form.Label>
                </div>
                <div className="col-2">
                    {swayIconBucketURL && (
                        <Image
                            alt={organization.name}
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
    }, [handleIconUpload, isLoadingIcon, organization.iconPath, organization.id, organization.name, swayIconBucketURL]);

    return (
        <div className="col py-2">
            <div className="row">
                <div className="col">
                    <SwayTextArea
                        field={{
                            name: `${swayFieldName}.summary`,
                            component: "textarea",
                            type: "text",
                            label: `${organization.name} Position Summary`,
                            isRequired: true,
                        }}
                        value={summary}
                        error={error}
                        setFieldValue={handleChange}
                        handleSetTouched={handleSetTouched}
                        helperText={`${organization.name} opinion of bill.`}
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
