import { titleize } from "app/frontend/sway_utils";

import { lazy, useCallback, useMemo } from "react";
import { sway } from "sway";

import ButtonUnstyled from "app/frontend/components/ButtonUnstyled";
import SuspenseFullScreen from "app/frontend/components/dialogs/SuspenseFullScreen";
import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
import BillSummaryMarkdown from "./BillSummaryMarkdown";
import { IS_MOBILE_PHONE } from "app/frontend/sway_constants";
const DialogWrapper = lazy(() => import("../dialogs/DialogWrapper"));

interface IProps {
    summary: string;
    bill_organization: sway.IBillOrganization | undefined;
    selectedOrganization: sway.IBillOrganizationBase | undefined;
    setSelectedOrganization: (org: sway.IBillOrganizationBase | undefined) => void;
}

const BillSummaryModal: React.FC<IProps> = ({
    summary,
    bill_organization,
    selectedOrganization,
    setSelectedOrganization,
}) => {
    const isSelected = useMemo(
        () => bill_organization?.name && bill_organization?.name === selectedOrganization?.name,
        [bill_organization?.name, selectedOrganization?.name],
    );

    const handleClick = useCallback(
        () => setSelectedOrganization(bill_organization),
        [bill_organization, setSelectedOrganization],
    );

    const renderSummary = useCallback(
        (isTruncated: boolean) => {
            if (!summary) return null;

            // TODO: Arbitrarily picked 200, should probably cut-off also at first bullet point or after first paragraph.
            const s = isTruncated ? `${summary.substring(0, 200).trim()}...` : summary;
            if (isTruncated) {
                return (
                    <>
                        <BillSummaryMarkdown summary={s} cutoff={1} handleClick={handleClick} />
                        <ButtonUnstyled onClick={handleClick} className="p-0 link no-underline">
                            Click/tap for more.
                        </ButtonUnstyled>
                    </>
                );
            } else {
                return <BillSummaryMarkdown summary={s} cutoff={1} handleClick={handleClick} />;
            }
        },
        [summary, handleClick],
    );

    const isOpen = useMemo(() => bill_organization?.name && isSelected, [bill_organization?.name, isSelected]);

    return (
        <>
            <div className={`my-2 px-1 brighter-item-hover ${isOpen ? "d-none" : ""}`}>{renderSummary(true)}</div>
            {isOpen && (
                <SuspenseFullScreen>
                    <DialogWrapper
                        open={true}
                        size={IS_MOBILE_PHONE ? "xl" : "lg"}
                        fullscreen={IS_MOBILE_PHONE || undefined}
                        setOpen={() => setSelectedOrganization(undefined)}
                        style={{ margin: 0 }}
                    >
                        <div>
                            <div>
                                <OrganizationIcon bill_organization={bill_organization} maxWidth={100} />
                                {bill_organization?.name.toLowerCase() !== "sway" && (
                                    <p className="bold">{titleize(bill_organization?.name as string)}</p>
                                )}
                            </div>
                            {summary && renderSummary(false)}
                        </div>
                    </DialogWrapper>
                </SuspenseFullScreen>
            )}
        </>
    );
};

export default BillSummaryModal;
