import { PropsWithChildren } from "react";
import { Label } from "app/frontend/components/ui/label";
import { cn } from "app/frontend/lib/utils";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { type TFeatureNoteKey } from "app/frontend/components/admin/creator/featureNotes";

interface IProps extends PropsWithChildren {
    name: string;
    label?: string;
    required?: boolean;
    helperText?: string;
    error?: string;
    className?: string;
    featureNote?: TFeatureNoteKey;
}

// @lat: [[bill-creator-shared-field-design#Why FieldShell uses named theme colours]]
export const FieldShell: React.FC<IProps> = ({
    name,
    label,
    required,
    helperText,
    error,
    className,
    featureNote,
    children,
}) => {
    const labelNode = label && (
        <Label htmlFor={name} className="flex-wrap font-semibold leading-snug">
            {label}
            <span className="font-normal text-muted-foreground">{required ? " *" : " (Optional)"}</span>
        </Label>
    );

    return (
        <div className={cn("flex flex-col gap-1.5", className)}>
            {featureNote && labelNode ? (
                <div className="flex flex-wrap items-center gap-1.5">
                    {labelNode}
                    <FeatureInfo note={featureNote} />
                </div>
            ) : (
                labelNode
            )}
            {children}
            {helperText && <p className="text-xs text-muted-foreground">{helperText}</p>}
            {error && (
                <p id={`${name}-error`} className="text-xs font-medium text-destructive" role="alert">
                    {error}
                </p>
            )}
        </div>
    );
};

export default FieldShell;
