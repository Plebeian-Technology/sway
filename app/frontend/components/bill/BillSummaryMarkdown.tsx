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
                {!summary ? <div>&nbsp;</div> : <ReactMarkdown remarkPlugins={[remarkGfm]}>{summary}</ReactMarkdown>}
            </div>
        </div>
    );
};

export default BillSummaryMarkdown;
