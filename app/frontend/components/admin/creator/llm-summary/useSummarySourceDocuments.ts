import { router, usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { ISummarySourceDocuments } from "app/frontend/components/admin/creator/llm-summary/types";

interface IPageProps {
    summary_source_documents?: ISummarySourceDocuments | null;
    [key: string]: unknown;
}

interface IUseSummarySourceDocuments {
    documents: ISummarySourceDocuments | null;
    loading: boolean;
    load: () => void;
}

// @lat: [[bill-creator-summary-tab#Why each input opens a modal of its own]]
export const useSummarySourceDocuments = (): IUseSummarySourceDocuments => {
    const documents = usePage<IPageProps>().props.summary_source_documents ?? null;
    const [loading, setLoading] = useState<boolean>(false);

    const load = useCallback(() => {
        setLoading(true);
        router.reload({
            only: ["summary_source_documents"],
            onFinish: () => setLoading(false),
        });
    }, []);

    return { documents, loading, load };
};
