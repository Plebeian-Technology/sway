import { Button } from "app/frontend/components/ui/button";
import { Textarea } from "app/frontend/components/ui/textarea";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { SUPPLEMENTAL_TESTIMONY_TITLE_ID } from "app/frontend/components/admin/creator/llm-summary/summaryTitleIds";

interface IProps {
    value: string;
    onChange: (value: string) => void;
    onClear?: () => void;
    onSave?: () => void;
    storedValue?: string;
}

// @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended#The field is a sub-section, not a form row]]
const SupplementalTestimonyField: React.FC<IProps> = ({ value, onChange, onClear, onSave, storedValue }) => (
    <div className="flex flex-col gap-3 rounded-xl border-neo border-border bg-surface-2 p-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="flex min-w-0 items-center gap-1.5">
                <h4 id={SUPPLEMENTAL_TESTIMONY_TITLE_ID} className="text-base font-medium">
                    Supplemental testimony <span className="text-sm font-normal text-muted-foreground">(optional)</span>
                </h4>
                <FeatureInfo note="summary.supplementalTestimony" />
            </div>
            <div className="flex flex-wrap items-center gap-3">
                {onSave && value !== (storedValue ?? "") ? (
                    <span className="flex items-center gap-1.5">
                        <Button
                            type="button"
                            variant="default"
                            size="sm"
                            onClick={onSave}
                            data-testid="btn-save-supplemental-testimony"
                        >
                            Save testimony
                        </Button>
                        <FeatureInfo note="summary.saveTestimony" />
                    </span>
                ) : null}
                {onClear && storedValue ? (
                    <span className="flex items-center gap-1.5">
                        <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            onClick={onClear}
                            data-testid="btn-clear-supplemental-testimony"
                        >
                            Clear saved testimony
                        </Button>
                        <FeatureInfo note="summary.clearTestimony" />
                    </span>
                ) : null}
            </div>
        </div>
        <Textarea
            id="supplemental-testimony"
            aria-labelledby={SUPPLEMENTAL_TESTIMONY_TITLE_ID}
            rows={4}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder="Paste additional testimony or supplemental context here (optional)"
            data-testid="textarea-supplemental-testimony"
        />
    </div>
);

export default SupplementalTestimonyField;
