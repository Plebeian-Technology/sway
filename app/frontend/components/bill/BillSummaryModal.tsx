import { titleize } from "app/frontend/sway_utils";

import { useCallback, useMemo } from "react";
import { sway } from "sway";

import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
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

const BillSummaryModal: React.FC<IProps> = ({
    summary,
    organizationPosition,
    selectedOrganization,
    setSelectedOrganization,
}) => {
    const organization = useMemo(() => organizationPosition?.organization, [organizationPosition?.organization]);

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
                {renderSummary}
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
                            <OrganizationIcon organization={organization} maxWidth={100} />
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
