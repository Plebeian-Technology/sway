import { Suspense, lazy, useCallback, useState } from "react";
import { Button, Form } from "react-bootstrap";
import { sway } from "sway";

import { Divider } from "@mui/material";
import {
    ICreatorOrganizations,
    TOrganizationError,
    TOrganizationOption,
} from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
import { Support } from "app/frontend/sway_constants";
import { notify, titleize } from "app/frontend/sway_utils";
import { FiPenTool, FiPlus } from "react-icons/fi";
import BillSummaryMarkdown from "../../bill/BillSummaryMarkdown";
import SwayTextArea from "../../forms/SwayTextArea";

const FileUploadModal = lazy(() => import("app/frontend/components/dialogs/FileUploadModal"));

interface IProps {
    index: number;
    organization: TOrganizationOption;
    error: TOrganizationError | undefined;
}

const BillCreatorOrganization: React.FC<IProps> = ({ index, organization, error }) => {
    const { setData } = useFormContext<ICreatorOrganizations>();

    const summary = organization.summary ?? "";
    const support = organization.support ?? Support.For;

    const [showUploadModal, setShowUploadModal] = useState<boolean>(false);
    const handleShowHideUploadModal = useCallback(() => setShowUploadModal((current) => !current), []);

    const onIconUpload = useCallback(
        (fileUpload: sway.files.IFileUpload) => {
            if (!organization.value) return;

            setData(`organizations.${index}.icon_path`, fileUpload.bucketFilePath);
            notify({ level: "success", title: "Icon Uploaded. Click to Close." });
        },
        [index, organization.value, setData],
    );

    return (
        <div className="col my-2">
            <div className="row align-items-center justify-content-center">
                <h3>{organization.label}</h3>
                {error?.label && <div className="text-danger">{error.label}</div>}
            </div>
            <div className="row align-items-center justify-content-center">
                <div className="col-6">
                    <Form.Group>
                        <Form.Label>Support</Form.Label>
                        <Form.Check
                            type="switch"
                            checked={support === Support.For}
                            onChange={() =>
                                setData(
                                    `organizations.${index}.support`,
                                    support === Support.For ? Support.Against : Support.For,
                                )
                            }
                            label={titleize(support === Support.For ? Support.For : Support.Against)}
                        />
                        {error?.support && <div className="text-danger">{error.support}</div>}
                    </Form.Group>
                </div>
                <div className="col-6">
                    {organization.icon_path ? (
                        <div>
                            <OrganizationIcon organization={organization} />
                            <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                                Update Icon <FiPenTool />
                            </Button>
                        </div>
                    ) : (
                        <Button variant="outline-primary" onClick={handleShowHideUploadModal}>
                            Add Icon <FiPlus />
                        </Button>
                    )}
                    {error?.icon_path && <div className="text-danger">{error.icon_path}</div>}
                </div>
            </div>
            <Divider className="my-5" />
            <div className="row align-items-center justify-content-center">
                <div className="col-6">
                    <SwayTextArea<ICreatorOrganizations>
                        field={{
                            // @ts-expect-error - not a valid key
                            name: `organizations.${index}.summary`,
                            component: "textarea",
                            type: "text",
                            label: `${organization.label} Position Summary`,
                            isRequired: true,
                        }}
                        value={summary}
                        error={error?.summary}
                        helperText={`${organization.label} opinion of bill.`}
                    />
                </div>
                <div className="col-6">
                    <BillSummaryMarkdown summary={summary} />
                </div>
            </div>
            <Suspense fallback={<FullScreenLoading />}>
                {showUploadModal && (
                    <FileUploadModal
                        fileName={organization.label}
                        currentFilePath={organization.icon_path || null}
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
