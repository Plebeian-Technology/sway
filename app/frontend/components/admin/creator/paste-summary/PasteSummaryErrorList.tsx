import type { IValidationError } from "app/frontend/types/bill_creator";

interface IProps {
    errors: IValidationError[];
    // @lat: [[json-pointer-offset-resolution#resolveJsonPointerOffset]]
    onErrorClick: (pointer: string) => void;
}

const PasteSummaryErrorList: React.FC<IProps> = ({ errors, onErrorClick }) => {
    return (
        <ul aria-label="Validation errors" data-testid="paste-summary-errors" className="flex flex-col gap-1 text-sm">
            {errors.map((er, i) => (
                <li key={`${er.path}-${i}`}>
                    <button
                        type="button"
                        data-testid={`paste-summary-error-${i}`}
                        onClick={() => onErrorClick(er.path)}
                        className="cursor-pointer rounded-md border-0 bg-transparent px-1.5 py-1 text-left underline hover:bg-accent/15"
                    >
                        <span className="text-xs text-muted-foreground">{er.path}</span>{" "}
                        <span className="text-destructive">{er.message}</span>
                    </button>
                </li>
            ))}
        </ul>
    );
};

export default PasteSummaryErrorList;
