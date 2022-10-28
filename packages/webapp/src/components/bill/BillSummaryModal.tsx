import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { titleize } from "@sway/utils";

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

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
    organization,
    selectedOrganization,
    setSelectedOrganization,
    isUseMarkdown,
}) => {
    const isSelected = organization && organization.name === selectedOrganization?.name;

    const handleClick = () => setSelectedOrganization(organization);

    const iconPath = () => {
        if (!organization) {
            return "/sway-us-light.png";
        }
        if (organization.name === "Sway") {
            return "/sway-us-light.png";
        }
        if (!organization.iconPath || !localeName) {
            return "/sway-us-light.png";
        }
        return `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}%2Forganizations%2F${organization.iconPath}?alt=media`;
    };

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
                            {organization.iconPath && (
                                <SwaySvg
                                    style={{ width: 50, height: 50 }}
                                    src={iconPath()}
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
