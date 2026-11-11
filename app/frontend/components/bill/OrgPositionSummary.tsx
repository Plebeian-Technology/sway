// @lat: [[ai-unreviewed-notice-component-design#Why OrgPositionSummary.tsx is a component for one paragraph]]

import AiUnreviewedNotice from "app/frontend/components/bill/AiUnreviewedNotice";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";

interface IProps {
    summary: string | null | undefined;
    summaryAiUnreviewed: boolean | undefined;
    className?: string;
    // @lat: [[ai-unreviewed-notice-component-design#Why OrgPositionSummary.tsx is a component for one paragraph]]
    prefix?: React.ReactNode;
}

const OrgPositionSummary: React.FC<IProps> = ({ summary, summaryAiUnreviewed, className, prefix }) => {
    if (!summary) return null;

    return (
        <>
            <div className={className}>
                {prefix && <span>{prefix}</span>}
                <LazyBillSummaryMarkdown summary={summary} />
            </div>
            <AiUnreviewedNotice unreviewed={summaryAiUnreviewed} />
        </>
    );
};

export default OrgPositionSummary;
