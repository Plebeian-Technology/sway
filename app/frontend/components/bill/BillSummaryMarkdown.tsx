import { ExternalLink } from "lucide-react";
import ReactMarkdown, { ExtraProps } from "react-markdown";
import remarkGfm from "remark-gfm";

import AiUnreviewedNotice from "app/frontend/components/bill/AiUnreviewedNotice";
import "app/frontend/components/bill/bill-summary-markdown.css";
import { isSafeExternalHref } from "app/frontend/sway_utils/safeHref";

export interface IProps {
    summary: string | undefined;
    cutoff?: number;
    handleClick?: () => void;
    // @lat: [[ai-unreviewed-notice-component-design#Why BillSummaryMarkdown.tsx attaches the notice, not each bill layout]]
    aiUnreviewed?: boolean;
    billId?: number;
    billLink?: string | null;
}

const hostOf = (href: string): string | null => {
    try {
        return new URL(href, window.location.origin).host;
    } catch {
        return null;
    }
};

const MarkdownLink = (props: React.AnchorHTMLAttributes<HTMLAnchorElement> & ExtraProps) => {
    const href = props.href || "";
    if (!isSafeExternalHref(href)) {
        return <span>{props.children}</span>;
    }
    const host = hostOf(href);
    const domainIsDifferent = host !== null && host !== location.host;
    return (
        <a href={href} target="_blank" rel="noopener noreferrer">
            {props.children}
            {domainIsDifferent && <ExternalLink className="text-primary inline align-middle ml-0.5 size-4" />}
        </a>
    );
};

// @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
const BillSummaryMarkdown: React.FC<IProps> = ({
    handleClick: _handleClick,
    summary,
    aiUnreviewed,
    billId,
    billLink,
}) => {
    return (
        <div className="bill-summary-markdown break-words">
            {!summary ? (
                <div>&nbsp;</div>
            ) : (
                <>
                    <ReactMarkdown
                        remarkPlugins={[remarkGfm]}
                        disallowedElements={["img"]}
                        unwrapDisallowed
                        components={{
                            a: MarkdownLink,
                        }}
                    >
                        {summary}
                    </ReactMarkdown>
                    <AiUnreviewedNotice unreviewed={aiUnreviewed} billId={billId} billLink={billLink} />
                </>
            )}
        </div>
    );
};

export default BillSummaryMarkdown;
