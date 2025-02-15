import { lazy, Suspense, useCallback, useMemo } from "react";
import { sway } from "sway";

import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
import { IS_MOBILE_PHONE } from "app/frontend/sway_constants";
import { Button } from "react-bootstrap";
import BillSummaryMarkdown from "./BillSummaryMarkdown";
const DialogWrapper = lazy(() => import("../dialogs/DialogWrapper"));

interface IProps {
    summary: string;
    organization: sway.IOrganization | undefined;
    selectedOrganization: sway.IOrganizationBase | undefined;
    setSelectedOrganization: (org: sway.IOrganizationBase | undefined) => void;
}

const BillSummaryModal: React.FC<IProps> = ({
    summary,
    organization,
    selectedOrganization,
    setSelectedOrganization,
}) => {
    const isSelected = useMemo(
        () => organization?.name && organization?.name === selectedOrganization?.name,
        [organization?.name, selectedOrganization?.name],
    );

    const handleClick = useCallback(
        () => setSelectedOrganization(organization),
        [organization, setSelectedOrganization],
    );

    const renderSummary = useCallback(
        (isTruncated: boolean) => {
            if (!summary) return null;

            // TODO: Arbitrarily picked 200, should probably cut-off also at first bullet point or after first paragraph.
            const s = isTruncated ? `${summary.substring(0, 300).trim()}...` : summary;
            if (isTruncated) {
                return (
                    <Button onClick={handleClick} className="w-100 p-4" variant="light border-0 text-start">
                        <BillSummaryMarkdown summary={s} cutoff={1} handleClick={handleClick} />
                        <span className="text-primary">Click/tap for more.</span>
                    </Button>
                );
            } else {
                return <BillSummaryMarkdown summary={s} cutoff={1} handleClick={handleClick} />;
            }
        },
        [summary, handleClick],
    );

    const isOpen = useMemo(() => organization?.name && isSelected, [organization?.name, isSelected]);

    return (
        <>
            <div className={"my-2"}>{renderSummary(true)}</div>
            {isOpen && (
                <Suspense fallback={null}>
                    <DialogWrapper
                        open={true}
                        size={IS_MOBILE_PHONE ? "xl" : "lg"}
                        fullscreen={IS_MOBILE_PHONE || undefined}
                        setOpen={() => setSelectedOrganization(undefined)}
                        style={{ margin: 0 }}
                    >
                        <div>
                            <div className="mb-3">
                                <OrganizationIcon organization={organization} maxWidth={100} />
                            </div>
                            {summary && renderSummary(false)}
                        </div>
                    </DialogWrapper>
                </Suspense>
            )}
        </>
    );
};

export default BillSummaryModal;
