import { FiExternalLink } from "react-icons/fi";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface IProps {
    summary: string | undefined;
    cutoff?: number; // cut off after number of paragraphs
    handleClick?: () => void;
}

const BillSummaryMarkdown: React.FC<IProps> = ({ handleClick, summary }) => {
    return (
        <div onClick={handleClick} className="pointer">
            <div>
                {!summary ? (
                    <div>&nbsp;</div>
                ) : (
                    <ReactMarkdown
                        remarkPlugins={[remarkGfm]}
                        components={{
                            a: (props) => {
                                const href = props.href || "";
                                const linkIsAbsolute = href.startsWith("http");
                                const domainIsDifferent = linkIsAbsolute && new URL(href).host !== location.host;
                                return (
                                    <a href={href} target="_blank" rel="noopener noreferrer" role="link">
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
                            },
                        }}
                    >
                        {summary}
                    </ReactMarkdown>
                )}
            </div>
        </div>
    );
};

export default BillSummaryMarkdown;
