// @lat: [[per-bill-grid-virtualization#Why the column headings sit outside the scrolling area]]

import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { COLUMN_TEMPLATE } from "app/frontend/components/admin/creator/per-bill-grid/constants";

const GridHeaderRow: React.FC = () => (
    <tr
        aria-rowindex={1}
        className="grid text-xs font-semibold uppercase tracking-wide border-b border-border-soft"
        style={{ gridTemplateColumns: COLUMN_TEMPLATE }}
    >
        <th scope="col" className="px-3 py-2 text-left font-semibold">
            Bill
        </th>
        <th scope="col" className="px-3 py-2 text-left font-semibold">
            Status
        </th>
        <th scope="col" aria-label="Stage" className="px-3 py-2 text-left font-semibold">
            <span className="flex items-center gap-1.5">
                Stage
                <FeatureInfo note="pipeline.stageColumn" />
            </span>
        </th>
        <th scope="col" className="px-3 py-2 text-left font-semibold">
            Stages
        </th>
        <th scope="col" className="px-3 py-2 text-left font-semibold">
            Started
        </th>
        <th scope="col" className="px-3 py-2 text-left font-semibold">
            Actions
        </th>
    </tr>
);

export { GridHeaderRow };
export default GridHeaderRow;
