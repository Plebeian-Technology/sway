import { logDev } from "@sway/utils";
import { useField } from "formik";
import { forwardRef, useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { handleError } from "../../utils";
import { withEmojis } from "../../utils/emoji";
import SwayTextArea from "../forms/SwayTextArea";
import BillSummaryMarkdown from "./BillSummaryMarkdown";

interface IProps {
    field: sway.IFormField;
}

const BillCreatorSummary = forwardRef(
    ({ field }: IProps, ref: React.Ref<string>) => {
        const [formikField] = useField(field.name);
        const [summary, setSummary] = useState<string>(formikField.value || "");

        const handleSetSummary = useCallback(
            async (fieldname: string, string: string) => {
                setSummary(withEmojis(string));
            },
            [],
        );

        useEffect(() => {
            // @ts-ignore
            ref.current = summary;
        }, [summary]);

        useEffect(() => {
            if (formikField.value && !summary) {
                logDev("BILL CREATOR - SUMMARY LOAD");
                handleSetSummary("", formikField.value).catch(handleError);
            }
        }, [summary, formikField.value]);

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
