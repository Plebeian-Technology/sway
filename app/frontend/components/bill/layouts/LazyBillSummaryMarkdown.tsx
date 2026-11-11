import { lazy, Suspense } from "react";

import type { IProps } from "app/frontend/components/bill/BillSummaryMarkdown";

// @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
const BillSummaryMarkdown = lazy(() => import("app/frontend/components/bill/BillSummaryMarkdown"));

const LazyBillSummaryMarkdown: React.FC<IProps> = (props) => (
    <Suspense fallback={<div className="break-words">&nbsp;</div>}>
        <BillSummaryMarkdown {...props} />
    </Suspense>
);

export default LazyBillSummaryMarkdown;
