import { withEmojis } from "app/frontend/sway_utils";
import { lazy, Suspense, useCallback, useMemo } from "react";
import { sway } from "sway";
import { Textarea } from "app/frontend/components/ui/textarea";
import BillCreatorSummaryAudio from "app/frontend/components/admin/creator/BillCreatorSummaryAudio";
import { useCreatorField } from "app/frontend/components/admin/creator/hooks/useCreatorField";
import { FieldShell } from "app/frontend/components/admin/creator/fields/FieldShell";

// @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
const BillSummaryMarkdown = lazy(() => import("app/frontend/components/bill/BillSummaryMarkdown"));

interface IProps<T> {
    swayField: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

const SummaryField = <T,>({ swayField, onBlur }: IProps<T>) => {
    const { data, setValue, errorMessage, disabled } = useCreatorField(swayField);

    const field: sway.IFormField<T> = useMemo(
        () => ({
            ...swayField,
            disabled,
        }),
        [disabled, swayField],
    );

    // @lat: [[bill-creator-form-state#The summary field reads current form data]]
    const summary = data.summary ?? "";

    const fieldName = (field.name as string) ?? "summary";

    const onChange = useCallback(
        (e: React.ChangeEvent<HTMLTextAreaElement>) => {
            const next = withEmojis(e.target.value);
            setValue(next);
        },
        [setValue],
    );

    return (
        <div className="flex flex-col gap-4">
            <FieldShell
                name={fieldName}
                label={field.label}
                required={field.isRequired}
                helperText={field.helperText}
                error={errorMessage}
                featureNote="creator.summaryField"
            >
                <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                    <Textarea
                        id={fieldName}
                        name={fieldName}
                        value={summary}
                        rows={field.rows ?? 12}
                        disabled={field.disabled}
                        onChange={onChange}
                        onBlur={onBlur}
                        aria-invalid={errorMessage ? true : undefined}
                        aria-describedby={errorMessage ? `${fieldName}-error` : undefined}
                    />
                    <div className="rounded-xl border-neo border-border bg-card p-3 shadow-neo">
                        <a
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex min-h-11 items-center text-xs font-semibold uppercase tracking-wide text-primary underline sm:min-h-0 sm:py-0"
                            href="https://www.markdownguide.org/basic-syntax"
                        >
                            Markdown Syntax Guide
                        </a>
                        <div className="mt-2">
                            <Suspense fallback={<div className="text-sm text-muted-foreground">Loading preview…</div>}>
                                <BillSummaryMarkdown summary={summary} />
                            </Suspense>
                        </div>
                    </div>
                </div>
            </FieldShell>
            <BillCreatorSummaryAudio onBlur={onBlur} />
        </div>
    );
};

export default SummaryField;
