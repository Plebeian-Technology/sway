import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IProps {
    pasteChars: number;
    pasteShareOfLimit: number | null;
    displacedLetterCount: number | null;
}

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const TestimonyPasteNotice: React.FC<IProps> = ({ pasteChars, pasteShareOfLimit, displacedLetterCount }) => {
    const share = pasteShareOfLimit ?? 0;
    const percent = Math.round(share * 100);
    const limitChars = share > 0 ? Math.round(pasteChars / share) : pasteChars;

    return (
        <p className="text-sm tabular-nums lining-nums">
            {`Your pasted text is in the prompt exactly as you saved it. It was not cleaned. It fills ${percent}% of the size limit — ${pasteChars.toLocaleString()} of ${limitChars.toLocaleString()} characters.`}
            {displacedLetterCount !== null && displacedLetterCount > 0
                ? ` Your pasted text is joined first, so it is never left out. ${countNoun(displacedLetterCount, "letter", "letters")} did not fit within the size limit.`
                : ""}
        </p>
    );
};

export default TestimonyPasteNotice;
