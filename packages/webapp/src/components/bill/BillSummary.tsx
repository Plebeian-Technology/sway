import { OpenInNew } from "@mui/icons-material";
import { Link as MaterialLink, Typography } from "@mui/material";
import { flatten } from "@sway/utils";
import { Fragment } from "react";
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

    const handleOpenMoreInfo = (e: React.MouseEvent<HTMLAnchorElement>) => {
        if (handleClick) {
            e.preventDefault();
            handleClick();
        }
    };

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
                    <Typography
                        style={{ margin: "20px auto" }}
                        className={klass ? klass : ""}
                        key={i}
                        component={"p"}
                        variant={"body1"}
                        color="textPrimary"
                    >
                        {p}
                    </Typography>
                );
            }
            return <BillSummaryBulletsList key={i} points={points} klass={klass} />;
        })
        .concat(<div key="divider" className="my-2 border border-bottom" />)
        .concat(
            !link && !handleClick
                ? []
                : [
                      <Fragment key={"link"}>
                          <MaterialLink
                              onClick={handleOpenMoreInfo}
                              target="_blank"
                              rel="noopener noreferrer"
                              href={link || "https://sway.vote"}
                              variant={"body1"}
                              component="span"
                              className="bold"
                          >
                              More Info&nbsp;
                              <OpenInNew />
                          </MaterialLink>
                      </Fragment>,
                  ],
        );

    return <>{paragraphs}</>;
};

export default BillSummary;
