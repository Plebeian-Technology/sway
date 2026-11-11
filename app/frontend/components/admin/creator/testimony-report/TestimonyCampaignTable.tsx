import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import CollapsiblePanel from "app/frontend/components/CollapsiblePanel";
import { ITestimonyCampaignDraft } from "app/frontend/components/admin/creator/llm-summary/types";
import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IProps {
    rows: ITestimonyCampaignDraft[];
}

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const COLLAPSE_THRESHOLD = 8;

const formatCount = (count: number): string => count.toLocaleString();

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const campaignNameCell = (row: ITestimonyCampaignDraft): string =>
    `${countNoun(row.sender_count, "person", "people")} sent this letter`;

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const addedWordsCell = (row: ITestimonyCampaignDraft): string =>
    `${row.added_words_characters.toLocaleString()} characters of senders' own words`;

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const addedWordsBoundNote = (row: ITestimonyCampaignDraft): string | null => {
    if (!row.senders_added_words_left_out) return null;

    return `The limit on added words was reached. ${countNoun(row.senders_added_words_left_out, "sender's", "senders'")} own words were not kept.`;
};

const CampaignRows: React.FC<{ rows: ITestimonyCampaignDraft[] }> = ({ rows }) => (
    <TableBody>
        {rows.map((row) => {
            const note = addedWordsBoundNote(row);
            return (
                <TableRow key={row.content_hash}>
                    <TableCell className="tabular-nums lining-nums">{campaignNameCell(row)}</TableCell>
                    <TableCell className="tabular-nums lining-nums">{formatCount(row.sender_count)}</TableCell>
                    <TableCell className="tabular-nums lining-nums">{formatCount(row.letter_count)}</TableCell>
                    <TableCell className="tabular-nums lining-nums">
                        <div className="flex flex-col gap-1">
                            <span>{addedWordsCell(row)}</span>
                            {note && <span className="text-xs text-warning">{note}</span>}
                        </div>
                    </TableCell>
                </TableRow>
            );
        })}
    </TableBody>
);

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const TestimonyCampaignTable: React.FC<IProps> = ({ rows }) => {
    if (rows.length === 0) {
        return <p className="text-sm italic text-muted-foreground">No campaign letters were found on this bill.</p>;
    }

    const table = (
        <Table>
            <TableHeader>
                <TableRow>
                    <TableHead scope="col">Campaign</TableHead>
                    <TableHead scope="col">Senders</TableHead>
                    <TableHead scope="col">Letters</TableHead>
                    <TableHead scope="col">Added words</TableHead>
                </TableRow>
            </TableHeader>
            <CampaignRows rows={rows} />
        </Table>
    );

    if (rows.length <= COLLAPSE_THRESHOLD) return table;

    return (
        <CollapsiblePanel
            storageKey="sway:pipeline-llm:accordion:testimony-campaigns"
            title={`Campaigns (${rows.length.toLocaleString()})`}
            defaultOpen={false}
        >
            {table}
        </CollapsiblePanel>
    );
};

export default TestimonyCampaignTable;
