import { BILLS_SEARCH_PLACEHOLDER } from "app/frontend/components/bill/list-layouts/types";

interface IProps {
    id: string;
    className?: string;
    value: string;
    onChange: (term: string) => void;
}

// @lat: [[bill-list-layouts-design#BillsSearchInput.tsx]]
const BillsSearchInput: React.FC<IProps> = ({ id, className, value, onChange }) => (
    <input
        id={id}
        type="search"
        className={className}
        data-testid="input-search-bills"
        placeholder={BILLS_SEARCH_PLACEHOLDER}
        value={value}
        onChange={(event) => onChange(event.target.value)}
    />
);

export default BillsSearchInput;
