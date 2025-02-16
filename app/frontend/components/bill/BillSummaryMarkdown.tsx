import { FiExternalLink } from "react-icons/fi";
import ReactMarkdown, { ExtraProps } from "react-markdown";
import remarkGfm from "remark-gfm";

interface IProps {
    summary: string | undefined;
    cutoff?: number; // cut off after number of paragraphs
    handleClick?: () => void;
}

const MarkdownLink = (props: React.AnchorHTMLAttributes<HTMLAnchorElement> & ExtraProps) => {
    const href = props.href || "";
    const linkIsAbsolute = href.startsWith("http");
    const domainIsDifferent = linkIsAbsolute && new URL(href).host !== location.host;
    return (
        <a href={href} target="_blank" rel="noopener noreferrer">
            {props.children}
            {domainIsDifferent && (
                <FiExternalLink
                    style={{
                        fontSize: "1em",
                        color: "primary",
                        verticalAlign: "middle",
                        marginLeft: "2px",
                    }}
                />
            )}
        </a>
    );
};

const BillSummaryMarkdown: React.FC<IProps> = ({ handleClick: _handleClick, summary }) => {
    return (
        <div>
            {!summary ? (
                <div>&nbsp;</div>
            ) : (
                <ReactMarkdown
                    remarkPlugins={[remarkGfm]}
                    components={{
                        a: MarkdownLink,
                    }}
                    className={"text-break"}
                >
                    {summary}
                </ReactMarkdown>
            )}
        </div>
    );
};

export default BillSummaryMarkdown;
