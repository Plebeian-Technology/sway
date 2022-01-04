import { FormHelperText, Card } from "@mui/material";
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
            <Card variant="outlined">
                {!summary ? (
                    <div>&nbsp;</div>
                ) : (
                    <ReactMarkdown
                        className="p-2"
                        children={summary}
                        remarkPlugins={[remarkGfm]}
                        linkTarget="_blank"
                    />
                )}
            </Card>
            <FormHelperText>
                A preview of the summary rendered with Markdown
            </FormHelperText>
        </div>
    );
};

export default BillSummaryMarkdown;
