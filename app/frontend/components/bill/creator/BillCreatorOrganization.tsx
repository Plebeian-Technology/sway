import { useField, useFormikContext } from "formik";
import { Suspense, lazy, useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "react-bootstrap";
import { sway } from "sway";

import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
import { useAxiosPost } from "app/frontend/hooks/useAxios";
import { handleError } from "app/frontend/sway_utils";
import { FiPenTool, FiPlus } from "react-icons/fi";
import { withEmojis } from "../../../sway_utils/emoji";
import SwayTextArea from "../../forms/SwayTextArea";
import BillSummaryMarkdown from "../BillSummaryMarkdown";

const FileUploadModal = lazy(() => import("app/frontend/components/dialogs/FileUploadModal"));

interface IProps {
    swayFieldName: string;
    organization: sway.IOrganizationBase;
    handleSetTouched: (fieldname: string) => void;
    error: string;
}

const BillCreatorOrganization: React.FC<IProps> = ({ swayFieldName, organization, handleSetTouched, error }) => {
    const { setFieldValue } = useFormikContext();
    const [formikField] = useField(swayFieldName);

    const [summary, setSummary] = useState<string>(formikField?.value?.summary ?? "");
    const handleChangeSummary = useCallback(async (_fieldname: string, fieldvalue: string) => {
        withEmojis(fieldvalue)
            .then((emojis) => {
                setSummary(emojis);
            })
            .catch(console.error);
    }, []);

    // Async updating of formik field using a useEffect and local summary state
    useEffect(() => {
        setFieldValue(`${swayFieldName}.summary`, summary).catch(console.error);
    }, [summary, setFieldValue, swayFieldName]);

    const [showUploadModal, setShowUploadModal] = useState<boolean>(false);
    const handleShowHideUploadModal = useCallback(() => setShowUploadModal((current) => !current), []);

    const { items: updatedOrg, post: updateOrganization } = useAxiosPost<sway.IOrganizationBase>(
        `/organizations/${organization.id}`,
        { method: "put" },
    );
    const onIconUpload = useCallback(
        (fileUpload: sway.files.IFileUpload) => {
            if (!organization.id) return;

            updateOrganization({ icon_path: fileUpload.bucketFilePath })
                .then(handleShowHideUploadModal)
                .catch(handleError);
        },
        [handleShowHideUploadModal, organization.id, updateOrganization],
    );

    const org = useMemo(() => updatedOrg || organization, [updatedOrg, organization]);

    return (
        <div className="col my-2">
            <div className="row">
                <div className="col">
                    <SwayTextArea
                        field={{
                            name: `${swayFieldName}.summary`,
                            component: "textarea",
                            type: "text",
                            label: `${org.name} Position Summary`,
                            isRequired: true,
                        }}
                        value={summary}
                        error={error}
                        setFieldValue={handleChangeSummary}
                        handleSetTouched={handleSetTouched}
                        helperText={`${org.name} opinion of bill.`}
                    />
                    {org.iconPath ? (
                        <div className="row">
                            <div className="col-8">
                                <OrganizationIcon organization={updatedOrg || organization} />
                            </div>
                            <div className="col-4">
                                <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                                    Update Icon <FiPenTool />
                                </Button>
                            </div>
                        </div>
                    ) : (
                        <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                            Add Icon <FiPlus />
                        </Button>
                    )}
                </div>
                <div className="col">
                    <BillSummaryMarkdown summary={summary} />
                </div>
            </div>
            <Suspense fallback={<FullScreenLoading />}>
                {showUploadModal && (
                    <FileUploadModal
                        fileName={org.name}
                        currentFilePath={org.iconPath || null}
                        onHide={handleShowHideUploadModal}
                        callback={onIconUpload}
                        accept="image/*"
                    />
                )}
            </Suspense>
        </div>
    );
};

export default BillCreatorOrganization;
