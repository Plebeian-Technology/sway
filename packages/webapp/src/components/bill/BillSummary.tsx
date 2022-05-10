import { flatten } from "@sway/utils";
import { FiExternalLink } from "react-icons/fi";
import BillSummaryBulletsList from "./BillSummaryBulletsList";
import BillSummaryTextWithLink from "./BillSummaryTextWithLink";

interface IProps {
    summary: string;
    klass?: string; // extra classes to add to typography
    cutoff?: number; // cut off after number of paragraphs
    handleClick?: () => void;
}

const BillSummary: React.FC<IProps> = ({ summary, klass, cutoff, handleClick }) => {
    if (!summary) return <div className="pb-3">No summary available.</div>;

    const [text, link] = summary.split("ENDING");

    const _paragraphs = flatten(text.split("NEWLINE"));
    const paragraphs = _paragraphs
        .filter((_: string, i: number) => (!cutoff ? true : i < cutoff))
        .map((p: string, i: number) => {
            if (p.includes("<a href")) {
                return <BillSummaryTextWithLink key={i} text={p} />;
            }

            const points: string[] = p
                .split(";")
                .map((s) => s.trim())
                .filter(Boolean)
                .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
                .map((s) => (s.endsWith(".") ? s : `${s}.`));

            if (points.length < 2) {
                return (
                    <p key={i} className={klass ? klass : ""} style={{ margin: "20px auto" }}>
                        {p}
                    </p>
                );
            }
            return <BillSummaryBulletsList key={i} points={points} klass={klass} />;
        })
        .concat(<div key="divider" className="my-2 border border-bottom" />)
        .concat(
            !link && !handleClick
                ? []
                : [
                      <a
                          key={"link"}
                          target="_blank"
                          rel="noopener noreferrer"
                          href={link || "https://sway.vote"}
                          className="bold"
                      >
                          More Info&nbsp;
                          <FiExternalLink />
                      </a>,
                  ],
        );

    return <>{paragraphs}</>;
};

export default BillSummary;
