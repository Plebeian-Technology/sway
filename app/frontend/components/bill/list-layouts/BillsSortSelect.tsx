import { BILLS_SORT_OPTIONS, type BillsSortValue } from "app/frontend/components/bill/list-layouts/types";

interface IProps {
    id: string;
    className?: string;
    value: BillsSortValue;
    onChange: (value: BillsSortValue) => void;
}

const BillsSortSelect: React.FC<IProps> = ({ id, className, value, onChange }) => (
    <select
        id={id}
        className={className}
        data-testid="select-sort-bills"
        value={value}
        onChange={(event) => onChange(event.target.value as BillsSortValue)}
    >
        {BILLS_SORT_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
                {option.label}
            </option>
        ))}
    </select>
);

export default BillsSortSelect;
