import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import { usePage } from "@inertiajs/react";
import { titleize } from "app/frontend/sway_utils";
import { sortBy } from "lodash";
import { useCallback, useMemo, useRef } from "react";
import { ISelectOption, sway } from "sway";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { useSwayFormContext } from "app/frontend/components/admin/creator/context/useSwayFormContext";
import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { FieldShell } from "app/frontend/components/admin/creator/fields/FieldShell";
import { type TFeatureNoteKey } from "app/frontend/components/admin/creator/featureNotes";

interface IProps<T> {
    swayField: sway.IFormField<T>;
    options?: ISelectOption[];
    // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
    onStored?: (name: string, override?: Record<string, unknown>) => void;
    featureNote?: TFeatureNoteKey;
}

// @lat: [[bill-creator-shared-field-design#Why SelectField ignores swayField.multi]]
const SelectField = <T,>({ swayField, options, onStored, featureNote }: IProps<T>) => {
    const { data, setData } = useSwayFormContext<IApiBillCreator>();
    const errorMessage = useErrorMessage(swayField);
    const [locale] = useSwayLocale();
    const pageProps = usePage().props as Record<string, unknown>;
    const pageLegislators = pageProps.legislators as sway.ILegislator[] | undefined;

    const derivedOptions = useMemo<ISelectOption[]>(() => {
        if (options) return options;
        if (swayField.possibleValues) return swayField.possibleValues;

        // @lat: [[bill-creator-shared-field-design#How SelectField derives options, tracks open state, and mirrors FormData]]
        if (swayField.name === "legislator_id") {
            const legislators = pageLegislators ?? [];
            return sortBy(
                legislators.map((l) => ({
                    label: l.district
                        ? `${titleize(l.last_name)}, ${titleize(l.first_name)} (${l.district.region_code} - ${l.district.number})`
                        : `${titleize(l.last_name)}, ${titleize(l.first_name)}`,
                    value: String(l.id),
                })),
                ["label"],
            );
        }

        return [];
    }, [options, pageLegislators, swayField]);

    const rawValue = (data as unknown as Record<string, unknown>)[swayField.name as string];
    const currentValue = useMemo(() => {
        if (rawValue === null || rawValue === undefined || rawValue === "") return "";
        if (typeof rawValue === "string" || typeof rawValue === "number") return String(rawValue);
        if (typeof rawValue === "object" && rawValue !== null && "value" in (rawValue as Record<string, unknown>)) {
            const extractedValue = (rawValue as { value: unknown }).value ?? "";
            if (typeof extractedValue === "string" || typeof extractedValue === "number") return String(extractedValue);
            return "";
        }
        return "";
    }, [rawValue]);

    // @lat: [[bill-creator-shared-field-design#How SelectField derives options, tracks open state, and mirrors FormData]]
    const disabled = Boolean(swayField.disabled || swayField.disableOn?.(locale));

    // @lat: [[bill-creator-shared-field-design#How SelectField derives options, tracks open state, and mirrors FormData]]
    const isOpenRef = useRef<boolean>(false);

    const onValueChange = useCallback(
        (nextValue: string) => {
            // @lat: [[bill-creator-shared-field-design#How SelectField derives options, tracks open state, and mirrors FormData]]
            setData(swayField.name as never, nextValue as never);
            // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
            onStored?.(swayField.name as string, { [swayField.name as string]: nextValue });
        },
        [setData, swayField.name, onStored],
    );

    // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
    const onTriggerBlur = useCallback(() => {
        if (isOpenRef.current) return;
        onStored?.(swayField.name as string);
    }, [onStored, swayField.name]);

    return (
        <FieldShell
            name={swayField.name as string}
            label={swayField.label}
            required={swayField.isRequired}
            helperText={swayField.helperText}
            error={errorMessage}
            featureNote={featureNote}
        >
            <Select
                value={currentValue || undefined}
                onValueChange={onValueChange}
                onOpenChange={(open) => {
                    isOpenRef.current = open;
                }}
                disabled={disabled}
            >
                {/* @lat: [[bill-creator-shared-field-design#How SelectField derives options, tracks open state, and mirrors FormData]] */}
                <SelectTrigger
                    id={swayField.name as string}
                    name={swayField.name as string}
                    onBlur={onTriggerBlur}
                    aria-invalid={errorMessage ? true : undefined}
                    aria-describedby={errorMessage ? `${swayField.name as string}-error` : undefined}
                >
                    <SelectValue placeholder="Select..." />
                </SelectTrigger>
                <SelectContent>
                    {derivedOptions.map((opt, i) => (
                        <SelectItem
                            key={`${String(opt.value)}-${i}`}
                            value={String(opt.value)}
                            className="min-h-11 md:min-h-0"
                        >
                            {opt.label}
                        </SelectItem>
                    ))}
                </SelectContent>
            </Select>
            {/* @lat: [[bill-creator-shared-field-design#How SelectField derives options, tracks open state, and mirrors FormData]] */}
            <input type="hidden" name={swayField.name as string} value={currentValue} />
        </FieldShell>
    );
};

export default SelectField;
