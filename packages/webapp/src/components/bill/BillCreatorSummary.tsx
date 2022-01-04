import { forwardRef, useEffect, useState } from "react";
import { sway } from "sway";
import { withEmojis } from "../../utils/emoji";
import SwayTextArea from "../forms/SwayTextArea";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    field: sway.IFormField;
}

const BillCreatorSummary = forwardRef(
    ({ field }: IProps, ref: React.Ref<string>) => {
        const [summary, setSummary] = useState<string>("");

        const handleSetSummary = async (fieldname: string, string: string) => {
            setSummary(withEmojis(string));
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
