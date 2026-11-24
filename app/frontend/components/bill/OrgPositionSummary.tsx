// @lat: [[ai-unreviewed-notice-component-design#Why OrgPositionSummary.tsx is a component for one paragraph]]

import AiUnreviewedNotice from "app/frontend/components/bill/AiUnreviewedNotice";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { sway } from "sway";

interface IProps {
    summary: string | null | undefined;
    summaryAiUnreviewed: boolean | undefined;
    className?: string;
    // @lat: [[ai-unreviewed-notice-component-design#Why OrgPositionSummary.tsx is a component for one paragraph]]
    prefix?: React.ReactNode;
    // @lat: [[organization-affiliation-labels#Organization affiliation labels#Every position carries its own tag]]
    organizationName?: string;
    sourceKind?: sway.IOrganizationPosition["source_kind"];
}

const OrgPositionSummary: React.FC<IProps> = ({
    summary,
    summaryAiUnreviewed,
    className,
    prefix,
    organizationName,
    sourceKind,
}) => {
    const sourceTag =
        organizationName === undefined ? null : (
            <div
                data-testid="org-position-source-tag"
                className="text-xs font-semibold uppercase text-muted-foreground"
            >
                {sourceKind === "organization"
                    ? PARITY_COPY.orgs.postedBy(organizationName)
                    : PARITY_COPY.orgs.compiledBySway}
            </div>
        );

    if (!summary) return sourceTag;

    return (
        <>
            {sourceTag}
            <div className={className}>
                {prefix && <span>{prefix}</span>}
                <LazyBillSummaryMarkdown summary={summary} />
            </div>
            <AiUnreviewedNotice unreviewed={summaryAiUnreviewed} />
        </>
    );
};

export default OrgPositionSummary;
