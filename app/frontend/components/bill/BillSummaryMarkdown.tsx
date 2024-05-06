import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface IProps {
    summary: string | undefined;
    klass?: string; // extra classes to add to typography
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
                        children={summary}
                        remarkPlugins={[remarkGfm]}
                    />
                )}
            </div>
            {/* <span>A preview of the summary rendered with Markdown</span> */}
        </div>
    );
};

export default BillSummaryMarkdown;
