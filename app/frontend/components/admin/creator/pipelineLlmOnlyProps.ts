// @lat: [[pipeline-llm-only-props-membership#Why specific entries are on the list]]
export const PIPELINE_LLM_ONLY_PROPS = [
    "bill",
    "legislation_pipeline_run",
    // @lat: [[partial-reload-prop-lists#Partial-reload prop lists by page]]
    "active_legislation_pipeline_run",
    "recent_pipeline_runs",
    "bill_artifact_mirrors",
    "fetched_bills",
    "stale_pipeline_run_count",
    "orphan_pipeline_run_count",
    // @lat: [[pipeline-llm-only-props-membership#Why specific entries are on the list]]
    "testimony_coverage",
    "testimony_campaign_drafts",
    "testimony_claimed_affiliations",
    "sending_service_domains",
    "sending_service_domains_total",
] as const;
