import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

interface IProps {
    // @lat: [[pipeline-terminal-alert-remedy-wording#Why PipelineErrorsAccordion's errors prop is NonNullable]]
    errors: NonNullable<ILegislationPipelineRun["errors"]>;
    status: ILegislationPipelineRun["status"];
}

const PipelineErrorsAccordion: React.FC<IProps> = ({ errors, status }) => {
    return (
        <details open={status === "failed"} data-testid="pipeline-errors-accordion" className="text-sm">
            <summary className="flex min-h-[44px] cursor-pointer items-center font-semibold">
                Errors (<span className="tabular-nums lining-nums">{errors.length}</span>)
            </summary>
            <ul className="mt-2 flex flex-col gap-1 text-xs">
                {errors.map((e, i) => (
                    <li key={i} className="break-words text-destructive">
                        <span className="font-semibold tabular-nums lining-nums">{e.external_id}</span> — {e.phase}:{" "}
                        {e.message}
                    </li>
                ))}
            </ul>
        </details>
    );
};

export default PipelineErrorsAccordion;
