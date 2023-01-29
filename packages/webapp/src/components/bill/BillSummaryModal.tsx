import { titleize } from "@sway/utils";
import { getDownloadURL, ref } from "firebase/storage";

import { useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { storage } from "../../firebase";
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

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
    organization,
    selectedOrganization,
    setSelectedOrganization,
    isUseMarkdown,
}) => {
    const [swayIconBucketURL, setSwayIconBucketURL] = useState<string | undefined>();
    useEffect(() => {
        const isSway = organization?.name?.toLowerCase() === "sway";
        const defaultValue = (() => {
            if (!organization) {
                return "/sway-us-light.png";
            }
            if (isSway) {
                return "/sway-us-light.png";
            }
            if (!organization.iconPath || !localeName) {
                return "/sway-us-light.png";
            }
        })();

        function loadURLToInputFiled() {
            if (!organization?.iconPath || !localeName) return;

            const storageRef = ref(
                storage,
                organization.iconPath.includes(localeName)
                    ? organization.iconPath
                    : `${localeName}/organizations/${organization.iconPath}?alt=media`,
            );
            getDownloadURL(storageRef).then(setSwayIconBucketURL).catch(console.error);
        }
        if (organization?.iconPath && !isSway && localeName) {
            loadURLToInputFiled();
        } else {
            setSwayIconBucketURL(defaultValue);
        }
    }, [localeName, organization?.iconPath]);

    const isSelected = organization && organization.name === selectedOrganization?.name;

    const handleClick = useCallback(
        () => setSelectedOrganization(organization),
        [organization, setSelectedOrganization],
    );

    const renderSummary = () => {
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
    };

    return (
        <>
            <div className={"brighter-item-hover"} onClick={handleClick}>
                {renderSummary()}
            </div>
            {organization && isSelected && (
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
                            {organization.name !== "Sway" && (
                                <p className="bold">{titleize(organization.name)}</p>
                            )}
                        </div>
                        {summary && renderSummary()}
                    </div>
                </DialogWrapper>
            )}
        </>
    );
};

export default BillSummaryModal;
