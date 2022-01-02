import { Divider, Link as MaterialLink, Typography } from "@mui/material";
import { flatten } from "@sway/utils";
import { Fragment } from "react";
import BillSummaryTextWithLink from "./BillSummaryTextWithLink";
import BillSummaryBulletsList from "./BillSummaryBulletsList";

interface IProps {
    summary: string;
    klass?: string; // extra classes to add to typography
    cutoff?: number; // cut off after number of paragraphs
    handleClick?: () => void;
}

const BillSummary: React.FC<IProps> = ({
    summary,
    klass,
    cutoff,
    handleClick,
}) => {
    if (!summary) return <Typography>No summary available.</Typography>;

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
            return (
                <BillSummaryBulletsList key={i} points={points} klass={klass} />
            );
        })
        .concat(<Divider key="divider" style={{ margin: 10 }} />)
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
                              style={{ fontWeight: "bold" }}
                          >
                              More Info
                          </MaterialLink>
                      </Fragment>,
                  ],
        );

    return <>{paragraphs}</>;
};

export default BillSummary;
