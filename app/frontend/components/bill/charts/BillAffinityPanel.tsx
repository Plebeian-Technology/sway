import { sway } from "sway";

import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";

import AffinityDistrictChart from "app/frontend/components/bill/charts/AffinityDistrictChart";
import { selectDistrictVoteSplits } from "app/frontend/components/bill/sway_utils/billPositions";

interface IProps {
    bill_score?: sway.IBillScore;
}

const BillAffinityPanel: React.FC<IProps> = ({ bill_score }) => {
    if (!bill_score || selectDistrictVoteSplits(bill_score).length === 0) return null;

    return (
        <Card className="bg-card/95" data-testid="bill-affinity-panel">
            <CardHeader>
                <CardTitle className="text-xl font-black">District affinity</CardTitle>
            </CardHeader>
            <CardContent>
                <AffinityDistrictChart score={bill_score} title="Net support vs oppose by district" />
            </CardContent>
        </Card>
    );
};

export default BillAffinityPanel;
