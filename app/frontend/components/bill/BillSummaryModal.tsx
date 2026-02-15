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

            // Cut-off at first markdown link, first paragraph, first bullet point, or 300 chars.
            const firstLinkOpenIndex = summary.indexOf("[");
            const firstParaIndex = summary.indexOf("\n\n");
            const bulletRegex = /\n\s*([\*\-\+]|\d+\.)\s/;
            const bulletMatch = summary.match(bulletRegex);
            const firstBulletIndex = bulletMatch?.index ?? -1;

            let cutoff = 300;
            if (firstLinkOpenIndex !== -1 && firstLinkOpenIndex < cutoff) cutoff = firstLinkOpenIndex;
            if (firstParaIndex !== -1 && firstParaIndex < cutoff) cutoff = firstParaIndex;
            if (firstBulletIndex !== -1 && firstBulletIndex < cutoff) cutoff = firstBulletIndex;

            // If the markers are at the very beginning, we ignore them for truncation point
            // and fallback to 300 to avoid empty summaries.
            if (cutoff <= 0) cutoff = 300;

            const truncated = summary.substring(0, cutoff).trim();
            const isActuallyTruncated = truncated.length < summary.trim().length;
            const s = isTruncated
                ? `${isActuallyTruncated && !truncated.endsWith(".") && !truncated.endsWith("...") ? truncated + "..." : truncated}`
                : summary;

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
