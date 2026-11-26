// @lat: [[ai-unreviewed-notice-component-design#Why OrgPositionSummary.tsx is a component for one paragraph]]

import AiUnreviewedNotice from "app/frontend/components/bill/AiUnreviewedNotice";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import { isSafeUrl } from "app/frontend/sway_utils/safeHref";
import {
    organizationPositionSourceLabel,
    organizationPositionTag,
} from "app/frontend/sway_utils/organizationPositionLabels";
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
    // @lat: [[organization-affiliation-labels#Organization affiliation labels#A compiled position names its source]]
    sourceUrl?: string | null;
}

const SourceLine: React.FC<{ label: string; url?: string | null }> = ({ label, url }) => (
    <div data-testid="org-position-source" className="text-xs text-muted-foreground">
        {url && isSafeUrl(url) ? (
            <a href={url} target="_blank" rel="noopener noreferrer" className="font-semibold hover:underline">
                {label}
                <span className="sr-only"> (opens in new tab)</span>
            </a>
        ) : (
            label
        )}
    </div>
);

const OrgPositionSummary: React.FC<IProps> = ({
    summary,
    summaryAiUnreviewed,
    className,
    prefix,
    organizationName,
    sourceKind,
    sourceUrl,
}) => {
    const sourceLabel = organizationPositionSourceLabel(sourceKind);
    const sourceTag =
        organizationName === undefined ? null : (
            <div
                data-testid="org-position-source-tag"
                className="text-xs font-semibold uppercase text-muted-foreground"
            >
                {organizationPositionTag(organizationName, sourceKind)}
            </div>
        );
    const sourceLine = sourceLabel ? <SourceLine label={sourceLabel} url={sourceUrl} /> : null;

    if (!summary)
        return (
            <>
                {sourceTag}
                {sourceLine}
            </>
        );

    return (
        <>
            {sourceTag}
            {sourceLine}
            <div className={className}>
                {prefix && <span>{prefix}</span>}
                <LazyBillSummaryMarkdown summary={summary} />
            </div>
            <AiUnreviewedNotice unreviewed={summaryAiUnreviewed} />
        </>
    );
};

export default OrgPositionSummary;
