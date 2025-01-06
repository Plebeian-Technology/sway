import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { withEmojis } from "app/frontend/sway_utils";
import { forwardRef, Ref, useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import SwayTextArea from "../forms/SwayTextArea";
import BillSummaryMarkdown from "./BillSummaryMarkdown";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";

interface IProps<T> {
    field: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}
const BillCreatorSummary = <T,>({ field, onBlur }: IProps<T>, ref: React.Ref<string>) => {
    const { data, errors } = useFormContext<IApiBillCreator>();
    const summaryRef = ref as React.MutableRefObject<string>;

    const [summary, setSummary] = useState<string>(data.summary ?? "");
    const onChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
        setSummary(withEmojis(e.target.value));
    }, []);

    useEffect(() => {
        summaryRef.current = summary;
    }, [summaryRef, summary]);

    return (
        <div className="col">
            <div className="row">
                <div className="col-xs-12 col-sm-6">
                    <SwayTextArea<T>
                        field={field}
                        value={summary}
                        onChange={onChange}
                        error={errors["summary"]}
                        helperText={field.helperText}
                        onBlur={onBlur}
                    />
                </div>
                <div className="col-xs-12 col-sm-6">
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
};

// https://stackoverflow.com/a/78692562/6410635
export default forwardRef(BillCreatorSummary) as <T>(
    props: IProps<T> & { ref?: Ref<string> },
) => ReturnType<typeof BillCreatorSummary>;
