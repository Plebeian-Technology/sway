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
const extractAnchorTextFromString = (string: string): [string, string, string][] => {
    const matches = [] as [string, string, string][];
    string.replace(/[^<]*(<a href="([^"]+)">([^<]+)<\/a>)/g, function (...args: string[]) {
        // @ts-expect-error - Argument of type 'any[]' is not assignable to parameter of type '[string, string, string]'.
        matches.push(Array.prototype.slice.call(args, 1, 4));
        return "";
    });

    return matches || [["", "", ""]];
};

// https://stackoverflow.com/a/30474868/6410635
const BillSummaryTextWithLink: React.FC<{ text: string }> = ({ text }) => {
    const matches = extractAnchorTextFromString(text);

    let final: (string | JSX.Element)[] = [];
    matches.forEach(([anchor, href, innerText], index: number) => {
        const toReplace = (final.pop() || text) as string;
        const replacer = toReplace.split(anchor);

        final = [
            ...final,
            ...[
                replacer[0],
                <a key={index} href={href} rel="noreferrer" target={"_blank"}>
                    {innerText}
                </a>,
                replacer[1],
            ],
        ];
    });

    return <span>{final}</span>;
};

export default BillSummaryTextWithLink;
