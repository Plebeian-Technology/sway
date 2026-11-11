import { usePage } from "@inertiajs/react";
import BillCreatorBillForm from "app/frontend/components/admin/creator/BillCreatorBillForm";
import BillCreatorLegislatorVotes from "app/frontend/components/admin/creator/BillCreatorLegislatorVotes";
import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import BillCreatorOrganizationDraftCache from "app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCache";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { organizationsFormKey } from "app/frontend/components/admin/creator/organizations/organizationsFormKey";
import { EEventKey } from "app/frontend/components/bill/creator/constants";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "app/frontend/components/ui/accordion";
import { useEffect, useState } from "react";
import { sway } from "sway";

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

const ACCORDION_NUMBER: Record<EEventKey, string> = {
    [EEventKey.BILL]: "01.",
    [EEventKey.LEGISLATOR_VOTES]: "02.",
    [EEventKey.ORGANIZATIONS]: "03.",
    [EEventKey.LLM_SUMMARY]: "04.",
    [EEventKey.PIPELINE]: "05.",
};

interface IPageProps {
    bill?: sway.IBill & { organizations?: sway.IOrganization[] };
    legislator_votes?: sway.ILegislatorVote[];
    [key: string]: unknown;
}

const readEventKeyFromUrl = (url?: string): EEventKey | null => {
    const queryIndex = url?.indexOf("?") ?? -1;
    const search = queryIndex >= 0 ? url!.slice(queryIndex) : window.location.search;
    return (new URLSearchParams(search).get("event_key") as EEventKey | null) ?? null;
};

const BillCreatorAccordions: React.FC<IProps> = ({ setCreatorDirty }) => {
    const page = usePage<IPageProps>();
    const bill = page.props.bill;
    const legislator_votes = page.props.legislator_votes ?? [];
    const isNoBillId = !(bill?.id && bill.id > 0);
    // @lat: [[bill-creator-shell#Why the Bill form is keyed by bill id]]
    const billFormKey = isNoBillId ? "new" : bill!.id;

    const urlEventKey = readEventKeyFromUrl(page.url);
    const [value, setValue] = useState<string>(urlEventKey ?? EEventKey.BILL);
    const [prevUrlEventKey, setPrevUrlEventKey] = useState<EEventKey | null>(urlEventKey);

    if (urlEventKey !== prevUrlEventKey) {
        setPrevUrlEventKey(urlEventKey);
        if (urlEventKey) {
            setValue(urlEventKey);
        }
    }

    useEffect(() => {
        const handleLocationChange = () => {
            const nextKey = readEventKeyFromUrl();
            if (nextKey) {
                setValue(nextKey);
            }
        };
        window.addEventListener("popstate", handleLocationChange);
        return () => window.removeEventListener("popstate", handleLocationChange);
    }, []);

    return (
        <Accordion type="single" collapsible value={value} onValueChange={setValue} className="w-full">
            <AccordionItem value={EEventKey.BILL}>
                <div className="flex items-center gap-1.5 [&>h3]:flex-1">
                    <AccordionTrigger className="min-h-11 rounded-lg px-2 py-3.5 text-base transition-colors data-[state=open]:bg-accent/10 data-[state=open]:font-bold data-[state=open]:text-primary md:text-lg">
                        <span className="flex flex-wrap items-start gap-3 wrap-break-word sm:items-center">
                            <span className="tabular-nums lining-nums text-sm text-muted-foreground">
                                {ACCORDION_NUMBER[EEventKey.BILL]}
                            </span>
                            <span>Details and Summary</span>
                        </span>
                    </AccordionTrigger>
                    <FeatureInfo note="creator.detailsAccordion" />
                </div>
                <AccordionContent>
                    <BillCreatorBillForm key={`bill-${billFormKey}`} setCreatorDirty={setCreatorDirty} />
                </AccordionContent>
            </AccordionItem>

            <AccordionItem value={EEventKey.LEGISLATOR_VOTES}>
                <div className="flex items-center gap-1.5 [&>h3]:flex-1">
                    <AccordionTrigger
                        className="min-h-11 rounded-lg px-2 py-3.5 text-base transition-colors data-[state=open]:bg-accent/10 data-[state=open]:font-bold data-[state=open]:text-primary md:text-lg"
                        disabled={isNoBillId}
                    >
                        <span className="flex flex-wrap items-start gap-3 wrap-break-word sm:items-center">
                            <span className="tabular-nums lining-nums text-sm text-muted-foreground">
                                {ACCORDION_NUMBER[EEventKey.LEGISLATOR_VOTES]}
                            </span>
                            <span>Legislator Votes</span>
                        </span>
                    </AccordionTrigger>
                    <FeatureInfo note="creator.legislatorVotesAccordion" />
                </div>
                <AccordionContent>
                    <BillCreatorLegislatorVotes
                        key={`${bill?.id || "new"}-${legislator_votes.map((v) => `${v.legislator_id}:${v.support}`).join(",")}`}
                    />
                </AccordionContent>
            </AccordionItem>

            <AccordionItem value={EEventKey.ORGANIZATIONS}>
                <div className="flex items-center gap-1.5 [&>h3]:flex-1">
                    <AccordionTrigger
                        className="min-h-11 rounded-lg px-2 py-3.5 text-base transition-colors data-[state=open]:bg-accent/10 data-[state=open]:font-bold data-[state=open]:text-primary md:text-lg"
                        disabled={isNoBillId}
                    >
                        <span className="flex flex-wrap items-start gap-3 wrap-break-word sm:items-center">
                            <span className="tabular-nums lining-nums text-sm text-muted-foreground">
                                {ACCORDION_NUMBER[EEventKey.ORGANIZATIONS]}
                            </span>
                            <span>Supporting/Opposing Arguments</span>
                        </span>
                    </AccordionTrigger>
                    <FeatureInfo note="creator.argumentsAccordion" />
                </div>
                <AccordionContent>
                    {/* @lat: [[bill-creator-organization-form#The cache outlives the organization-set form]] */}
                    <BillCreatorOrganizationDraftCache key={`org-drafts-${bill?.id ?? 0}`}>
                        <BillCreatorOrganizations
                            key={`orgs-${organizationsFormKey(bill)}`}
                            setCreatorDirty={setCreatorDirty}
                        />
                    </BillCreatorOrganizationDraftCache>
                </AccordionContent>
            </AccordionItem>

            <AccordionItem value={EEventKey.LLM_SUMMARY}>
                <div className="flex items-center gap-1.5 [&>h3]:flex-1">
                    <AccordionTrigger
                        className="min-h-11 rounded-lg px-2 py-3.5 text-base transition-colors data-[state=open]:bg-accent/10 data-[state=open]:font-bold data-[state=open]:text-primary md:text-lg"
                        disabled={isNoBillId}
                    >
                        <span className="flex flex-wrap items-start gap-3 wrap-break-word sm:items-center">
                            <span className="tabular-nums lining-nums text-sm text-muted-foreground">
                                {ACCORDION_NUMBER[EEventKey.LLM_SUMMARY]}
                            </span>
                            <span>LLM Summary</span>
                        </span>
                    </AccordionTrigger>
                    <FeatureInfo note="creator.llmSummaryAccordion" />
                </div>
                <AccordionContent>
                    {/* @lat: [[bill-creator-summary-tab#The LLM Summary accordion points to summary review]] */}
                    <p className="py-6 text-sm text-muted-foreground">
                        Review the LLM summary and news articles from the Summary tab.
                    </p>
                </AccordionContent>
            </AccordionItem>
        </Accordion>
    );
};

export default BillCreatorAccordions;
