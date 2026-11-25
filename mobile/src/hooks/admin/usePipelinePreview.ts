// @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";

export interface PipelinePreview {
    stages_requested: string[];
    stages_will_run: string[];
    stages_auto_included: string[];
    confirmation_required: boolean;
    confirmation_message: string | null;
    prereq_violations?: {
        stage: string;
        missing_artifact: string;
        bill_count: number;
        prerequisite: string;
    }[];
}

export interface UsePipelinePreviewResult {
    preview: PipelinePreview | null;
    load: (stages: string[], downloadMissingAssets: boolean) => Promise<void>;
}

export function usePipelinePreview(
    billId: number | null,
    initialPreview: PipelinePreview | null,
): UsePipelinePreviewResult {
    const [preview, setPreview] = useState<PipelinePreview | null>(initialPreview);
    const abortRef = useRef<AbortController | null>(null);

    useEffect(() => () => abortRef.current?.abort(), []);

    const load = useCallback(
        async (stages: string[], downloadMissingAssets: boolean) => {
            abortRef.current?.abort();
            if (stages.length === 0) {
                setPreview(null);
                return;
            }
            const ctrl = new AbortController();
            abortRef.current = ctrl;
            try {
                const res = await apiClient.get<{ pipeline_preview?: PipelinePreview | null }>(
                    Routes.adminBillCreatorPipelinePreview(billId, stages, downloadMissingAssets),
                    { signal: ctrl.signal },
                );
                if (!ctrl.signal.aborted) setPreview(res.pipeline_preview ?? null);
            } catch {
                if (!ctrl.signal.aborted) setPreview(null);
            }
        },
        [billId],
    );

    return { preview, load };
}
