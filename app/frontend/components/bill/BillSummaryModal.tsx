import { getStoragePath, titleize } from "app/frontend/sway_utils";

import { useCallback, useEffect, useMemo, useState } from "react";
import { sway } from "sway";

import DialogWrapper from "../dialogs/DialogWrapper";
import SwaySvg from "../SwaySvg";
import BillSummary from "./BillSummary";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    localeName: string | null | undefined;
    summary: string;
    billFirestoreId: string;
    organization: sway.IOrganization | null;
    selectedOrganization: sway.IOrganization | null;
    setSelectedOrganization: (org: sway.IOrganization | null) => void;
    isUseMarkdown: boolean;
}

const klasses = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const DEFAULT_ICON_PATH = "/sway-us-light.png";

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
    organization,
    selectedOrganization,
    setSelectedOrganization,
    isUseMarkdown,
}) => {
    const isSelected = useMemo(
        () => organization?.name && organization?.name === selectedOrganization?.name,
        [organization?.name, selectedOrganization?.name],
    );
    const [swayIconBucketURL, setSwayIconBucketURL] = useState<string | undefined>();

    useEffect(() => {
        const isSway = organization?.name?.toLowerCase() === "sway";
        setSwayIconBucketURL(DEFAULT_ICON_PATH);

        if (organization?.iconPath && !isSway && localeName) {
            // const storageRef = ref(
            //     storage,
            //     getStoragePath(organization.iconPath, localeName, "organizations"),
            // );
            // getDownloadURL(storageRef).then(setSwayIconBucketURL).catch(console.error);
        } else {
            // setSwayIconBucketURL(DEFAULT_ICON_PATH);
        }
    }, [localeName, organization?.iconPath, organization?.name]);

    const handleClick = useCallback(
        () => setSelectedOrganization(organization),
        [organization, setSelectedOrganization],
    );

    const renderSummary = useMemo(() => {
        if (isUseMarkdown) {
            return (
                <BillSummaryMarkdown
                    summary={summary}
                    klass={klasses.text}
                    cutoff={1}
                    handleClick={handleClick}
                />
            );
        }
        return (
            <BillSummary
                summary={summary}
                klass={klasses.text}
                cutoff={1}
                handleClick={handleClick}
            />
        );
    }, [isUseMarkdown, summary, handleClick]);

    return (
        <>
            <div className={"my-2 brighter-item-hover"} onClick={handleClick}>
                {renderSummary}
            </div>
            {organization && organization.name && isSelected && (
                <DialogWrapper
                    open={true}
                    setOpen={() => setSelectedOrganization(null)}
                    style={{ margin: 0 }}
                >
                    <div>
                        <div>
                            {swayIconBucketURL && (
                                <SwaySvg
                                    style={{ width: 50, height: 50 }}
                                    src={swayIconBucketURL}
                                    containerStyle={{ marginLeft: 0 }}
                                />
                            )}
                            {organization.name.toLowerCase() !== "sway" && (
                                <p className="bold">{titleize(organization.name)}</p>
                            )}
                        </div>
                        {summary && renderSummary}
                    </div>
                </DialogWrapper>
            )}
        </>
    );
};

export default BillSummaryModal;
