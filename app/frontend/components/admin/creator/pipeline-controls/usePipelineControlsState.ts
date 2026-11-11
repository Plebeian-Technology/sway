import { router, usePage } from "@inertiajs/react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { DEFAULT_STAGE_KEYS } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import type { IPageProps } from "app/frontend/components/admin/creator/pipeline-controls/types";
import { addressWithEmptyList } from "app/frontend/sway_utils/addressWithEmptyList";
import { currentAddressWithout } from "app/frontend/sway_utils/currentAddressWithout";

// @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
const PIPELINE_CONTROLS_ONLY_PROPS = ["selected_stages", "download_missing_assets", "pipeline_preview"];

// @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
const SELECTED_STAGES_PARAM = "selected_stages";
const PIPELINE_CONTROLS_URL_PARAMS = [SELECTED_STAGES_PARAM, "stages", "download_missing_assets"];

// @lat: [[bill-creator-pipeline-controls-panel#Why pipeline controls debounce URL updates]]
const URL_PUSH_DEBOUNCE_MS = 250;

const isDefaultStageSelection = (stages: readonly string[]): boolean => {
    if (stages.length !== DEFAULT_STAGE_KEYS.length) return false;
    const stageSet = new Set(stages);
    return stageSet.size === DEFAULT_STAGE_KEYS.length && DEFAULT_STAGE_KEYS.every((key) => stageSet.has(key));
};

export interface PipelineControlsState {
    selectedStages: string[];
    downloadMissingAssets: boolean;
    setSelectedStages: (next: string[]) => void;
    setDownloadMissingAssets: (next: boolean) => void;
}

// @lat: [[bill-creator-pipeline-controls-panel#Why pending state caches prevent click loss during round trips]]
export const usePipelineControlsState = (): PipelineControlsState => {
    const { props } = usePage<IPageProps>();

    const propSelectedStages = useMemo(() => props.selected_stages ?? [...DEFAULT_STAGE_KEYS], [props.selected_stages]);
    // @lat: [[bill-creator-pipeline-controls-panel#The page's control props follow URL precedence]]
    const propDownloadMissingAssets = props.download_missing_assets !== false;

    // @lat: [[bill-creator-pipeline-controls-panel#Why pending state caches prevent click loss during round trips]]
    const [pendingStages, setPendingStages] = useState<string[] | null>(null);
    const [pendingDma, setPendingDma] = useState<boolean | null>(null);
    const [lastReconciledPropStages, setLastReconciledPropStages] = useState(propSelectedStages);
    const [lastReconciledPropDma, setLastReconciledPropDma] = useState(propDownloadMissingAssets);

    const pendingValuesRef = useRef<{ selected_stages: string[]; download_missing_assets: boolean }>({
        selected_stages: propSelectedStages,
        download_missing_assets: propDownloadMissingAssets,
    });
    const pendingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    // @lat: [[bill-creator-pipeline-controls-panel#Why pending state caches prevent click loss during round trips]]
    const [changeNotYetSent, setChangeNotYetSent] = useState(false);

    // @lat: [[bill-creator-pipeline-controls-panel#Why deriving state during render reconciles server responses]]
    let effectivePendingStages = pendingStages;
    let effectivePendingDma = pendingDma;
    if (!changeNotYetSent && propSelectedStages !== lastReconciledPropStages) {
        setLastReconciledPropStages(propSelectedStages);
        if (pendingStages !== null) {
            setPendingStages(null);
            effectivePendingStages = null;
        }
    }
    if (!changeNotYetSent && propDownloadMissingAssets !== lastReconciledPropDma) {
        setLastReconciledPropDma(propDownloadMissingAssets);
        if (pendingDma !== null) {
            setPendingDma(null);
            effectivePendingDma = null;
        }
    }

    const selectedStages = effectivePendingStages ?? propSelectedStages;
    const downloadMissingAssets = effectivePendingDma ?? propDownloadMissingAssets;

    useEffect(() => {
        return () => {
            if (pendingTimerRef.current !== null) {
                clearTimeout(pendingTimerRef.current);
                pendingTimerRef.current = null;
            }
        };
    }, []);

    const flushUrlPush = useCallback(() => {
        pendingTimerRef.current = null;
        setChangeNotYetSent(false);
        const next = pendingValuesRef.current;

        // @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
        let address = currentAddressWithout(PIPELINE_CONTROLS_URL_PARAMS);

        const data: Record<string, string[] | string> = {};
        if (next.selected_stages.length > 0 && !isDefaultStageSelection(next.selected_stages)) {
            data.selected_stages = next.selected_stages;
            const url = new URL(address, window.location.origin);
            url.searchParams.delete(SELECTED_STAGES_PARAM);
            url.searchParams.delete(`${SELECTED_STAGES_PARAM}[]`);
            url.searchParams.delete("stages");
            url.searchParams.delete("stages[]");
            address = `${url.pathname}${url.search}`;
        } else if (next.selected_stages.length === 0) {
            // @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
            const url = new URL(address, window.location.origin);
            url.searchParams.delete("stages");
            url.searchParams.delete("stages[]");
            address = `${url.pathname}${url.search}`;
            address = addressWithEmptyList(address, SELECTED_STAGES_PARAM);
        } else {
            // @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
            const url = new URL(address, window.location.origin);
            url.searchParams.delete(SELECTED_STAGES_PARAM);
            url.searchParams.delete(`${SELECTED_STAGES_PARAM}[]`);
            url.searchParams.delete("stages");
            url.searchParams.delete("stages[]");
            address = `${url.pathname}${url.search}`;
        }
        if (!next.download_missing_assets) data.download_missing_assets = "0";

        router.visit(address, {
            method: "get",
            data,
            only: PIPELINE_CONTROLS_ONLY_PROPS,
            preserveState: true,
            preserveScroll: true,
            replace: true,
            async: true,
        });
    }, []);

    const schedulePush = useCallback(
        (overrides: Partial<{ selected_stages: string[]; download_missing_assets: boolean }>) => {
            pendingValuesRef.current = {
                selected_stages: overrides.selected_stages ?? pendingValuesRef.current.selected_stages,
                download_missing_assets:
                    overrides.download_missing_assets ?? pendingValuesRef.current.download_missing_assets,
            };
            if (pendingTimerRef.current !== null) clearTimeout(pendingTimerRef.current);
            pendingTimerRef.current = setTimeout(flushUrlPush, URL_PUSH_DEBOUNCE_MS);
            setChangeNotYetSent(true);
        },
        [flushUrlPush],
    );

    // @lat: [[bill-creator-pipeline-controls-panel#Why partial parameter updates retransmit full state snapshots]]
    const setSelectedStages = useCallback(
        (next: string[]) => {
            setPendingStages(next);
            schedulePush({ selected_stages: next, download_missing_assets: downloadMissingAssets });
        },
        [schedulePush, downloadMissingAssets],
    );
    const setDownloadMissingAssets = useCallback(
        (next: boolean) => {
            setPendingDma(next);
            schedulePush({ selected_stages: selectedStages, download_missing_assets: next });
        },
        [schedulePush, selectedStages],
    );

    return {
        selectedStages,
        downloadMissingAssets,
        setSelectedStages,
        setDownloadMissingAssets,
    };
};
