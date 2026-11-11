import BillPickerRow from "app/frontend/components/admin/creator/BillPickerRow";
import BillPickerSortToggle from "app/frontend/components/admin/creator/BillPickerSortToggle";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { shortBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { Combobox, type ComboboxOption } from "app/frontend/components/ui/combobox";
import { orderBy, sortBy } from "lodash";
import { useCallback, useMemo } from "react";
import { sway } from "sway";
import { navigateWithParams, setQueryParamCleared } from "app/frontend/sway_utils/url_navigation";

export const NEW_BILL_VALUE = "__new__";

interface IProps {
    tabKey: ETab;
    bills: sway.IBillPickerOption[];
    currentBillId: number | null;
    onValueChange: (next: string) => void;
    localeSelector?: React.ReactNode;
}

interface IPickerOption extends ComboboxOption {
    interestingScoreNormalized: number | null;
    latestActionDateTimeUtc: string | null;
}

const SORT_MODES = ["newest", "alpha", "score", "latest_action"] as const;
type TSortMode = (typeof SORT_MODES)[number];

// @lat: [[bill-creator-shell#The Bill Creator shell#Why the picker sort stays in the address]]
const readSortMode = (): TSortMode => {
    if (typeof window === "undefined") return "newest";
    const raw = new URLSearchParams(window.location.search).get("bill_creator_sort");
    return SORT_MODES.find((mode) => mode === raw) ?? "newest";
};

// @lat: [[bill-interesting-score#Why the picker keeps search and navigation separate]]
// @lat: [[bill-creator-shell#The Bill Creator shell#Why the picker sort stays in the address]]
const BillCreatorPicker: React.FC<IProps> = ({ tabKey, bills, currentBillId, onValueChange, localeSelector }) => {
    const sortMode = readSortMode();
    const setSortMode = useCallback((next: TSortMode) => {
        navigateWithParams(
            (params) => {
                if (next === "newest") {
                    setQueryParamCleared(params, "bill_creator_sort");
                } else {
                    params.set("bill_creator_sort", next);
                }
            },
            { only: ["bills"], errorTitle: "Could not update the bill picker order." },
        );
    }, []);

    const billOptions = useMemo<ComboboxOption[]>(() => {
        const mapped: IPickerOption[] = (bills ?? [])
            .filter((b) => Boolean(b.id))
            .map((b) => ({
                value: String(b.id),
                label: b.title ? `${b.external_id} — ${shortBillTitle(b.title)}` : String(b.external_id),
                keywords: [b.external_id, b.title, b.sponsor_name, b.status, b.chamber, b.category]
                    .filter(Boolean)
                    .join(" "),
                node: <BillPickerRow bill={b} />,
                interestingScoreNormalized: b.interesting_score_normalized,
                latestActionDateTimeUtc: b.latest_action_date_time_utc,
            }));

        const labelCaseInsensitive = (o: IPickerOption) => o.label.toLowerCase();

        if (sortMode === "latest_action") {
            return orderBy(
                mapped,
                [
                    (option) =>
                        option.latestActionDateTimeUtc === null
                            ? Number.NEGATIVE_INFINITY
                            : Date.parse(option.latestActionDateTimeUtc),
                    labelCaseInsensitive,
                ],
                ["desc", "asc"],
            );
        }
        if (sortMode === "score") {
            return orderBy(mapped, [(o) => o.interestingScoreNormalized ?? -1, labelCaseInsensitive], ["desc", "asc"]);
        }
        return sortMode === "alpha" ? sortBy(mapped, [labelCaseInsensitive]) : mapped;
    }, [bills, sortMode]);

    const pickerValue = currentBillId ? String(currentBillId) : NEW_BILL_VALUE;

    const isPipelineTab = tabKey === ETab.PipelineLlm;
    const sentinelLabel = isPipelineTab ? "All Bills" : "New Bill";
    const pickerLabel = isPipelineTab ? "Select Existing or All Bills" : "Select Existing or New Bill";

    const pinnedOption = useMemo<ComboboxOption>(
        () => ({ value: NEW_BILL_VALUE, label: sentinelLabel }),
        [sentinelLabel],
    );

    return (
        <div className="flex flex-col gap-2 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-1.5">
                    <span id="bill-creator-picker-label" className="text-xs font-semibold uppercase tracking-widest">
                        {pickerLabel}
                    </span>
                    <FeatureInfo note="creator.billPicker" />
                </div>
                <div className="flex flex-wrap items-center gap-2">
                    {localeSelector}
                    <BillPickerSortToggle sortMode={sortMode} onSortModeChange={setSortMode} />
                </div>
            </div>
            <Combobox
                id="bill-creator-picker"
                data-testid="bill-creator-picker"
                aria-labelledby="bill-creator-picker-label"
                value={pickerValue}
                onValueChange={onValueChange}
                options={billOptions}
                pinnedOption={pinnedOption}
                placeholder={sentinelLabel}
                searchPlaceholder="Search by bill number or title…"
                emptyText="No bills match your search."
                className="bg-muted"
                contentClassName="[&_input]:min-h-11 [&_[role=option]]:min-h-11 md:[&_input]:min-h-0 md:[&_[role=option]]:min-h-0"
            />
        </div>
    );
};

export default BillCreatorPicker;
