import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";

interface SharedAddressRow {
    address_ids: number[];
    user_count: number;
}

interface IProps {
    shared_addresses: SharedAddressRow[];
}

const pluralize = (count: number, singular: string, plural: string) => `${count} ${count === 1 ? singular : plural}`;

const SharedAddresses: React.FC<IProps> = ({ shared_addresses }) => {
    return (
        <div className="mx-auto w-full max-w-3xl space-y-8">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">Shared Addresses</h1>
                <p className="text-sm text-muted-foreground">
                    Addresses more than one registered user has given, shown by count only — no street, no coordinates.
                    A few people at one address is a normal household; a much larger count is worth a look. The address
                    id is shown so a flagged row can be looked up for review.
                </p>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle className="flex items-baseline justify-between gap-4 text-lg">
                        <span>Addresses</span>
                        <span className="text-sm font-normal text-muted-foreground">
                            {pluralize(shared_addresses.length, "address", "addresses")}
                        </span>
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    {shared_addresses.length === 0 ? (
                        <p className="text-sm text-muted-foreground">
                            No address has been given by more than one registered user.
                        </p>
                    ) : (
                        <ol className="divide-y divide-border">
                            {shared_addresses.map((row) => (
                                <li
                                    key={row.address_ids.join("-")}
                                    className="flex items-center justify-between gap-4 py-2"
                                >
                                    <span className="text-sm text-muted-foreground">
                                        Address ID {row.address_ids.join(", ")}
                                    </span>
                                    <span className="text-sm font-semibold tabular-nums text-foreground">
                                        {pluralize(row.user_count, "user", "users")}
                                    </span>
                                </li>
                            ))}
                        </ol>
                    )}
                </CardContent>
            </Card>
        </div>
    );
};

export default SharedAddresses;
