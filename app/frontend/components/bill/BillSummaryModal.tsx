import { titleize } from "app/frontend/sway_utils";

import { useCallback, useEffect, useMemo, useState } from "react";
import { sway } from "sway";

import DialogWrapper from "../dialogs/DialogWrapper";
import SwaySvg from "../SwaySvg";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    localeName: string | null | undefined;
    summary: string;
    billExternalId: string;
    organization: sway.IOrganization | null;
    selectedOrganization: sway.IOrganization | null;
    setSelectedOrganization: (org: sway.IOrganization | null) => void;
}

const klasses = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const DEFAULT_ICON_PATH = "/assets/sway-us-light.png";

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
    organization,
    selectedOrganization,
    setSelectedOrganization,
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
        return <BillSummaryMarkdown summary={summary} klass={klasses.text} cutoff={1} handleClick={handleClick} />;
    }, [summary, handleClick]);

    const isOpen = useMemo(() => organization?.name && isSelected, [organization?.name, isSelected]);

    return (
        <>
            <div
                className={`my-2 brighter-item-hover ${isOpen ? "d-none" : ""}`}
                onClick={handleClick}
            >
                {renderSummary}
            </div>
            {isOpen && (
                <DialogWrapper open={true} size="xl" fullscreen setOpen={() => setSelectedOrganization(null)} style={{ margin: 0 }}>
                    <div>
                        <div>
                            {swayIconBucketURL && (
                                <SwaySvg
                                    style={{ width: 50, height: 50 }}
                                    src={swayIconBucketURL}
                                    containerStyle={{ marginLeft: 0 }}
                                />
                            )}
                            {organization?.name.toLowerCase() !== "sway" && (
                                <p className="bold">{titleize(organization?.name as string)}</p>
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
