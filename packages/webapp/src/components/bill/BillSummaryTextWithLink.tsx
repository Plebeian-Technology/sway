import { Link as MaterialLink, Typography } from "@material-ui/core";
import { Fragment } from "react";

/**
 * https://stackoverflow.com/a/369174/6410635
 *
 * Returns:
 * 0 - the full anchor tag
 * 1 - the link from href
 * 2 - the text inside the anchor tag
 *
 * @param {string} string
 * @return {*}  {[string, string, string]}
 */
const extractAnchorTextFromString = (
    string: string,
): [string, string, string] => {
    const matches = [] as [string, string, string][];
    string.replace(
        /[^<]*(<a href="([^"]+)">([^<]+)<\/a>)/g,
        function (...args: any[]) { // eslint-disable-line
            // eslint-disable-next-line
            // @ts-ignore
            matches.push(Array.prototype.slice.call(args, 1, 4));
            return "";
        },
    );
    return matches[0] || ["", "", ""];
};

const BillSummaryTextWithLink: React.FC<{ text: string }> = ({ text }) => {
    const [anchor, href, innerText] = extractAnchorTextFromString(text);

    return (
        <Fragment>
            {text.split(anchor).map((s: string, idx: number) => {
                if (idx === 0) {
                    return (
                        <Fragment key={idx}>
                            <Typography
                                component={"span"}
                                variant={"body1"}
                                color="textPrimary"
                            >
                                {s}
                            </Typography>
                            <MaterialLink href={href} target={href.includes("sway.vote") ? "_self" : "_blank"}>
                                {innerText}
                            </MaterialLink>
                        </Fragment>
                    );
                }
                return (
                    <Typography
                        key={idx}
                        component={"span"}
                        variant={"body1"}
                        color="textPrimary"
                    >
                        {s}
                    </Typography>
                );
            })}
        </Fragment>
    );
};

export default BillSummaryTextWithLink;
