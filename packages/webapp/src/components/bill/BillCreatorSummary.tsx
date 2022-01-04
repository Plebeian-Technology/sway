import { forwardRef, useEffect, useState } from "react";
import { sway } from "sway";
import { getEmojiFromName } from "../../utils/emoji";
import SwayTextArea from "../forms/SwayTextArea";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    field: sway.IFormField;
}

const BillCreatorSummary = forwardRef(
    ({ field }: IProps, ref: React.Ref<string>) => {
        const [summary, setSummary] = useState<string>("");

        const handleSetSummary = async (fieldname: string, string: string) => {
            const words = (string || "").split(" ");
            const render = [] as string[];
            let i = 0;
            while (i < words.length) {
                const word = words[i];
                if (!word.startsWith(":")) {
                    render.push(word);
                } else {
                    const e = getEmojiFromName(word);
                    if (e) {
                        render.push(e);
                    } else {
                        render.push(word);
                    }
                }
                i++;
            }
            setSummary(render.join(" "));
        };

        useEffect(() => {
            // @ts-ignore
            ref.current = summary;
        }, [summary]);

        return (
            <div className="col">
                <div className="row">
                    <div className="col">
                        <SwayTextArea
                            field={field}
                            value={summary}
                            error={""}
                            setFieldValue={handleSetSummary}
                            handleSetTouched={() => null}
                            helperText={field.helperText}
                        />
                    </div>
                    <div className="col">
                        <BillSummaryMarkdown summary={summary} />
                    </div>
                </div>
            </div>
        );
    },
);

export default BillCreatorSummary;
