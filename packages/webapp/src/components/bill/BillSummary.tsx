import { Link as MaterialLink, Typography, useTheme } from "@material-ui/core";
import { flatten } from "@sway/utils";
import React from "react";

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
    const theme = useTheme();
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
            const points: string[] = p.split(";");
            if (points.length < 2) {
                return (
                    <Typography
                        style={{ margin: "5px auto" }}
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
                <ul key={i} style={{ marginTop: "1em" }}>
                    {points.map((point: string, index: number) => {
                        if (index === 0) {
                            const [intro, first] = point.split(":");
                            if (!first) {
                                return (
                                    <li
                                        key={index}
                                        style={{ marginLeft: theme.spacing(3) }}
                                    >
                                        <Typography
                                            className={klass ? klass : ""}
                                            key={i}
                                            component={"span"}
                                            variant={"body1"}
                                            color="textPrimary"
                                        >
                                            {point}
                                        </Typography>
                                    </li>
                                );
                            }
                            return (
                                <React.Fragment key={index}>
                                    <Typography
                                        className={klass ? klass : ""}
                                        component={"span"}
                                        variant={"body1"}
                                        color="textPrimary"
                                    >
                                        {`${intro}:`}
                                    </Typography>
                                    <li
                                        key={index}
                                        style={{ marginLeft: theme.spacing(3) }}
                                    >
                                        <Typography
                                            className={klass ? klass : ""}
                                            component={"span"}
                                            variant={"body1"}
                                            color="textPrimary"
                                        >
                                            {first}
                                        </Typography>
                                    </li>
                                </React.Fragment>
                            );
                        }
                        return (
                            <li
                                key={index}
                                style={{ marginLeft: theme.spacing(3) }}
                            >
                                <Typography
                                    className={klass ? klass : ""}
                                    key={i}
                                    component={"span"}
                                    variant={"body1"}
                                    color="textPrimary"
                                >
                                    {point}
                                </Typography>
                            </li>
                        );
                    })}
                </ul>
            );
        })
        .concat(
            !link && !handleClick
                ? []
                : [
                      <React.Fragment key={"link"}>
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
                      </React.Fragment>,
                  ],
        );

    return <>{paragraphs}</>;
};

export default BillSummary;
