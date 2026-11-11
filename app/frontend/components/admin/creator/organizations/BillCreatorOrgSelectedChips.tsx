import { TOrganizationOption } from "app/frontend/components/admin/creator/types";
import { X } from "lucide-react";
import { Badge } from "app/frontend/components/ui/badge";

interface IProps {
    selected: TOrganizationOption[];
    onRemove: (value: number | string) => void;
}

const BillCreatorOrgSelectedChips: React.FC<IProps> = ({ selected, onRemove }) => {
    if (selected.length === 0) return null;

    return (
        <div className="flex flex-wrap gap-2">
            {selected.map((org) => (
                <Badge key={`org-chip-${org.value}`} variant="solid" tone="neutral" className="gap-1 pr-1">
                    <span>{org.label}</span>
                    <button
                        type="button"
                        aria-label={`Remove ${org.label}`}
                        onClick={() => onRemove(org.value)}
                        className="-my-1 ml-1 inline-flex min-h-11 min-w-8 items-center justify-center rounded-full hover:bg-muted/50 sm:min-h-0 sm:min-w-0 sm:size-6"
                    >
                        <X aria-hidden className="size-3" />
                    </button>
                </Badge>
            ))}
        </div>
    );
};

export default BillCreatorOrgSelectedChips;
