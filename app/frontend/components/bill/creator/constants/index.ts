// @lat: [[bill-creator-tab-url-routing#Why app/frontend/components/bill/creator/constants/index.ts stays at this path for now]]
export enum ETab {
    Creator = "creator",
    Schedule = "schedule",
    PipelineLlm = "pipeline",
    Summary = "summary",
    Positions = "positions",
}

export enum EEventKey {
    BILL = "bill",
    ORGANIZATIONS = "organizations",
    LEGISLATOR_VOTES = "legislator_votes",
    LLM_SUMMARY = "llm_summary",
    PIPELINE = "pipeline",
}
