import { logDev } from "app/frontend/sway_utils";
import { useField } from "formik";
import { forwardRef, useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { handleError } from "../../sway_utils";
import { withEmojis } from "../../sway_utils/emoji";
import SwayTextArea from "../forms/SwayTextArea";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    field: sway.IFormField;
}

const BillCreatorSummary = forwardRef(({ field }: IProps, ref: React.Ref<string>) => {
    const [formikField] = useField(field.name);
    const [summary, setSummary] = useState<string>(formikField.value || "");

    const handleSetSummary = useCallback(async (_fieldname: string, string: string) => {
        withEmojis(string)
            .then((emojis) => {
                setSummary(emojis);
            })
            .catch(console.error);
    }, []);

    useEffect(() => {
        // @ts-expect-error - weird ref types
        ref.current = summary;
    }, [ref, summary]);

    useEffect(() => {
        if (formikField.value) {
            logDev("BillCreatorSummary.useEffect - set summary");
            handleSetSummary("", formikField.value).catch(handleError);
        }
    }, [formikField.value, handleSetSummary]);

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <SwayTextArea
                        field={{ ...field, ...formikField }}
                        value={summary}
                        error={""}
                        setFieldValue={handleSetSummary}
                        handleSetTouched={() => null}
                        helperText={field.helperText}
                    />
                </div>
                <div className="col">
                    <div>
                        <a target="_blank" rel="noreferrer" href="https://www.markdownguide.org/basic-syntax">
                            Markdown Syntax Guide
                        </a>
                    </div>
                    <BillSummaryMarkdown summary={summary} />
                </div>
            </div>
        </div>
    );
});

export default BillCreatorSummary;
