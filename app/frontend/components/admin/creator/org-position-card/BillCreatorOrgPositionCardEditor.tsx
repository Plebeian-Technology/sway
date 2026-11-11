import { useState } from "react";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Textarea } from "app/frontend/components/ui/textarea";
import { STANCE_OPTIONS, TStance } from "app/frontend/components/admin/creator/org-position-card/constants";

interface IProps {
    slug: string;
    initialOrgName: string;
    initialStance: TStance;
    initialSummary: string;
    onSave: (next: { orgName: string; stance: TStance; summary: string }) => void;
    onCancel: () => void;
}

// @lat: [[org-position-card-editing-and-approval-ui#Why the inline editor keeps its own copy of the values]]
const BillCreatorOrgPositionCardEditor: React.FC<IProps> = ({
    slug,
    initialOrgName,
    initialStance,
    initialSummary,
    onSave,
    onCancel,
}) => {
    const [draftOrgName, setDraftOrgName] = useState<string>(initialOrgName);
    const [draftStance, setDraftStance] = useState<TStance>(initialStance);
    const [draftSummary, setDraftSummary] = useState<string>(initialSummary);

    return (
        <div className="flex flex-col gap-2">
            <div className="flex flex-col gap-1">
                <Label htmlFor={`edit-org-name-${slug}`}>Organization name</Label>
                <Input
                    id={`edit-org-name-${slug}`}
                    data-testid="input-edit-org-name"
                    value={draftOrgName}
                    onChange={(e) => setDraftOrgName(e.target.value)}
                />
            </div>
            <div className="flex flex-col gap-1">
                <Label htmlFor={`edit-stance-${slug}`}>Position</Label>
                <Select value={draftStance} onValueChange={(v) => setDraftStance(v as TStance)}>
                    <SelectTrigger id={`edit-stance-${slug}`} data-testid="select-edit-stance-trigger">
                        <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                        {STANCE_OPTIONS.map((opt) => (
                            <SelectItem key={opt.value} value={opt.value}>
                                {opt.label}
                            </SelectItem>
                        ))}
                    </SelectContent>
                </Select>
            </div>
            <div className="flex flex-col gap-1">
                <Label htmlFor={`edit-summary-${slug}`}>Summary</Label>
                <Textarea
                    id={`edit-summary-${slug}`}
                    data-testid="textarea-edit-summary"
                    rows={3}
                    value={draftSummary}
                    onChange={(e) => setDraftSummary(e.target.value)}
                />
            </div>
            <div className="flex flex-wrap gap-2">
                <Button
                    type="button"
                    size="sm"
                    variant="default"
                    onClick={() => onSave({ orgName: draftOrgName, stance: draftStance, summary: draftSummary })}
                    data-testid="btn-save-edit-org-position"
                    // @lat: [[org-position-card-editing-and-approval-ui#Why the inline editor keeps its own copy of the values]]
                    title="Apply edits to this card. Edits live in the browser only — clicking Reject discards the draft entirely; clicking Approve commits the edits."
                >
                    Apply edits
                </Button>
                <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    onClick={onCancel}
                    data-testid="btn-cancel-edit-org-position"
                >
                    Cancel edit
                </Button>
            </div>
        </div>
    );
};

export default BillCreatorOrgPositionCardEditor;
