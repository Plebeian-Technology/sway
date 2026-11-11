import { sway } from "sway";

import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { splitBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import DistrictVotesChart from "app/frontend/components/bill/charts/DistrictVotesChart";
import TotalVotesChart from "app/frontend/components/bill/charts/TotalVotesChart";

interface IProps {
    bill: sway.IBill;
    bill_score?: sway.IBillScore;
    isAwaitingScoreUpdate?: boolean;
}

const BillChartsPanel: React.FC<IProps> = ({ bill, bill_score, isAwaitingScoreUpdate = false }) => {
    if (!bill_score) {
        return null;
    }

    const hasDistricts = Array.isArray(bill_score.districts) && bill_score.districts.length > 0;

    return (
        <Card className="bg-card/95" data-testid="bill-charts-panel">
            <CardHeader>
                <CardTitle className="text-xl font-black">{PARITY_COPY.bill.content.voteBreakdown}</CardTitle>
            </CardHeader>
            <CardContent className="grid gap-6">
                <div className="grid gap-2">
                    {/* @lat: [[bill-title-display#How a bill's title is shown#Where only the subject is shown]] */}
                    <TotalVotesChart score={bill_score} title={`All votes on ${splitBillTitle(bill.title).headline}`} />
                </div>
                {hasDistricts && (
                    <div className="grid gap-2">
                        <DistrictVotesChart score={bill_score} title="By district" />
                    </div>
                )}
                {isAwaitingScoreUpdate && (
                    <p className="text-sm font-semibold text-muted-foreground">Waiting for the latest score update…</p>
                )}
            </CardContent>
        </Card>
    );
};

export default BillChartsPanel;
