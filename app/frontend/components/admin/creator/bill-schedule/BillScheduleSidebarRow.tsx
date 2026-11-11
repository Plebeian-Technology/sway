import { sway } from "sway";
import { Button } from "app/frontend/components/ui/button";
import { calendarDayToDate, formatDate } from "app/frontend/sway_utils/datetimes";

interface IProps {
    bill: sway.IBillPickerOption;
    selectedBillId: number | null;
    date?: string;
    onSelectBill: (bill: sway.IBillPickerOption) => void;
}

const BillScheduleSidebarRow: React.FC<IProps> = ({ bill, selectedBillId, date, onSelectBill }) => {
    const isActive = selectedBillId === bill.id;
    return (
        <li className="flex flex-col gap-2 border-b-neo border-border-soft py-3 last:border-b-0 md:flex-row md:items-center md:justify-between">
            <div className="flex flex-col gap-1 text-sm">
                <span className="font-semibold tabular-nums lining-nums text-foreground">{bill.external_id}</span>
                <span className="text-foreground/80 line-clamp-2">{bill.title || "Untitled bill"}</span>
                {date && (
                    <span className="text-xs uppercase tracking-widest text-muted-foreground tabular-nums lining-nums">
                        {formatDate(calendarDayToDate(date))}
                    </span>
                )}
            </div>
            <Button
                type="button"
                size="sm"
                variant={isActive ? "default" : "outline"}
                disabled={isActive}
                onClick={() => onSelectBill(bill)}
                data-testid={`sidebar-select-${bill.external_id}`}
            >
                {isActive ? "Selected" : "Select"}
            </Button>
        </li>
    );
};

export default BillScheduleSidebarRow;
