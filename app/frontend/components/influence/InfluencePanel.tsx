import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { sway } from "sway";

interface IProps {
    influence: sway.IInfluence;
    swayLocaleLabel: string;
}

const InfluencePanel: React.FC<IProps> = ({ influence, swayLocaleLabel }) => {
    const stats = [
        { label: "Votes", value: influence?.count_bills_voted_on ?? 0 },
        { label: "Invites redeemed", value: influence?.count_invites_redeemed ?? 0 },
        { label: "Bills shared", value: influence?.count_bills_shared ?? 0 },
        { label: "Total sway", value: influence?.total_sway ?? 0 },
    ];

    return (
        <Card className="bg-card/95">
            <CardHeader className="gap-3">
                <CardTitle className="text-2xl font-black">Your influence in {swayLocaleLabel}</CardTitle>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
                {stats.map((stat) => (
                    <div key={stat.label} data-neo-surface="true" className="rounded-xl px-4 py-4">
                        <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                            {stat.label}
                        </div>
                        <div className="mt-2 text-3xl font-black text-foreground">{stat.value}</div>
                    </div>
                ))}
            </CardContent>
        </Card>
    );
};

export default InfluencePanel;
