import { titleize } from "app/frontend/sway_utils";

import { useCallback, useMemo } from "react";
import { sway } from "sway";

import ButtonUnstyled from "app/frontend/components/ButtonUnstyled";
import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
import { Image } from "react-bootstrap";
import DialogWrapper from "../dialogs/DialogWrapper";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    summary: string;
    organizationPosition: sway.IOrganizationPosition | undefined;
    selectedOrganization: sway.IOrganizationBase | undefined;
    setSelectedOrganization: (org: sway.IOrganizationBase | undefined) => void;
}

const klasses = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const DEFAULT_ICON_PATH = "/images/sway-us-light.png";

const BillSummaryModal: React.FC<IProps> = ({
    summary,
    organizationPosition,
    selectedOrganization,
    setSelectedOrganization,
}) => {
    const organization = organizationPosition?.organization;

    const isSelected = useMemo(
        () => organization?.name && organization?.name === selectedOrganization?.name,
        [organization?.name, selectedOrganization?.name],
    );

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
            <div className={`my-2 brighter-item-hover ${isOpen ? "d-none" : ""}`}>
            <ButtonUnstyled onClick={handleClick}>{renderSummary}</ButtonUnstyled>
            </div>
            {isOpen && (
                <DialogWrapper
                    open={true}
                    size="xl"
                    fullscreen
                    setOpen={() => setSelectedOrganization(undefined)}
                    style={{ margin: 0 }}
                >
                    <div>
                        <div>
                            {organization ? (
                                <OrganizationIcon organization={organization} maxWidth={100} />
                            ) : (
                                <Image src={DEFAULT_ICON_PATH} />
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
