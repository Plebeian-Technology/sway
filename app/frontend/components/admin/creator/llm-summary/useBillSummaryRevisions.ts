import { router, usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";

interface IPageProps {
    summary_revisions?: IBillSummaryRevision[] | null;
    [key: string]: unknown;
}

interface IUseBillSummaryRevisions {
    revisions: IBillSummaryRevision[] | null;
    loading: boolean;
    load: () => void;
}

// @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
export const useBillSummaryRevisions = (): IUseBillSummaryRevisions => {
    const revisions = usePage<IPageProps>().props.summary_revisions ?? null;
    const [loading, setLoading] = useState<boolean>(false);

    const load = useCallback(() => {
        setLoading(true);
        router.reload({
            only: ["summary_revisions"],
            onFinish: () => setLoading(false),
        });
    }, []);

    return { revisions, loading, load };
};
