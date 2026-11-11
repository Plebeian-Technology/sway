import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";

export interface UserAddressChangeRow {
    id: number;
    user_id: number;
    previous_address_id: number;
    new_address_id: number;
    deactivated_legislator_ids: number[];
    activated_legislator_ids: number[];
    deactivated_district_ids: number[];
    activated_district_ids: number[];
    previous_sway_locale_ids: number[];
    new_sway_locale_ids: number[];
    previous_sway_locale_names: string[];
    new_sway_locale_names: string[];
    prior_vote_count: number;
    prior_voted_bill_ids: number[];
    prior_voted_sway_locale_ids: number[];
    cross_district: boolean;
    cross_sway_locale: boolean;
    voted_before_switch: boolean;
    user_switch_count: number;
    created_at: string;
}

interface IProps {
    user_address_changes: UserAddressChangeRow[];
}

const pluralize = (count: number, singular: string, plural: string) => `${count} ${count === 1 ? singular : plural}`;

const formatIdList = (ids: number[]) => (ids.length === 0 ? "none" : ids.join(", "));

const formatLocaleList = (names: string[], ids: number[]) => {
    if (names.length > 0) {
        return names.join(", ");
    }
    return formatIdList(ids);
};

const formatPriorVotes = (row: UserAddressChangeRow) => {
    const base = pluralize(row.prior_vote_count, "vote", "votes");
    if (row.prior_voted_bill_ids.length === 0) {
        return base;
    }
    return `${base} (Bills: ${row.prior_voted_bill_ids.join(", ")})`;
};

const UserAddressChanges: React.FC<IProps> = ({ user_address_changes }) => {
    return (
        <div className="mx-auto w-full max-w-4xl space-y-8">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">Address Changes</h1>
                <p className="text-sm text-muted-foreground">
                    Audit trail of user address switches across districts and locales, shown by identifier and counts
                    only — no street, no coordinates.
                </p>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle className="flex items-baseline justify-between gap-4 text-lg">
                        <span>Switches</span>
                        <span className="text-sm font-normal text-muted-foreground">
                            {pluralize(user_address_changes.length, "switch", "switches")}
                        </span>
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    {user_address_changes.length === 0 ? (
                        <p className="text-sm text-muted-foreground">No user address switches have been recorded.</p>
                    ) : (
                        <ol className="divide-y divide-border">
                            {user_address_changes.map((row) => (
                                <li key={row.id} className="space-y-2 py-4">
                                    <div className="flex flex-wrap items-center justify-between gap-2">
                                        <div className="flex flex-wrap items-center gap-2">
                                            <span className="text-sm font-semibold tabular-nums text-foreground">
                                                User #{row.user_id}
                                            </span>
                                            <Badge
                                                variant="outline"
                                                tone={row.user_switch_count > 1 ? "warning" : "neutral"}
                                            >
                                                {pluralize(row.user_switch_count, "switch", "switches")} total
                                            </Badge>
                                            {row.user_switch_count > 1 ? (
                                                <Badge variant="solid" tone="warning">
                                                    Repeat switcher
                                                </Badge>
                                            ) : null}
                                            {row.cross_district ? (
                                                <Badge variant="solid" tone="warning">
                                                    Cross-district
                                                </Badge>
                                            ) : null}
                                            {row.cross_sway_locale ? (
                                                <Badge variant="solid" tone="danger">
                                                    Cross-locale
                                                </Badge>
                                            ) : null}
                                            {row.voted_before_switch ? (
                                                <Badge variant="solid" tone="info">
                                                    Voted before switch
                                                </Badge>
                                            ) : null}
                                        </div>
                                        <span className="text-xs tabular-nums text-muted-foreground">
                                            {row.created_at}
                                        </span>
                                    </div>

                                    <dl className="grid gap-1 text-xs text-muted-foreground sm:grid-cols-2">
                                        <div>
                                            <dt className="inline font-medium text-foreground">Address: </dt>
                                            <dd className="inline tabular-nums">
                                                Address #{row.previous_address_id} {"->"} #{row.new_address_id}
                                            </dd>
                                        </div>
                                        <div>
                                            <dt className="inline font-medium text-foreground">Locales: </dt>
                                            <dd className="inline">
                                                {formatLocaleList(
                                                    row.previous_sway_locale_names,
                                                    row.previous_sway_locale_ids,
                                                )}{" "}
                                                {"->"}{" "}
                                                {formatLocaleList(row.new_sway_locale_names, row.new_sway_locale_ids)}
                                            </dd>
                                        </div>
                                        <div>
                                            <dt className="inline font-medium text-foreground">Districts: </dt>
                                            <dd className="inline tabular-nums">
                                                {formatIdList(row.deactivated_district_ids)} {"->"}{" "}
                                                {formatIdList(row.activated_district_ids)}
                                            </dd>
                                        </div>
                                        <div>
                                            <dt className="inline font-medium text-foreground">Legislators: </dt>
                                            <dd className="inline tabular-nums">
                                                {formatIdList(row.deactivated_legislator_ids)} {"->"}{" "}
                                                {formatIdList(row.activated_legislator_ids)}
                                            </dd>
                                        </div>
                                        <div className="sm:col-span-2">
                                            <dt className="inline font-medium text-foreground">Prior votes: </dt>
                                            <dd className="inline tabular-nums">{formatPriorVotes(row)}</dd>
                                        </div>
                                    </dl>
                                </li>
                            ))}
                        </ol>
                    )}
                </CardContent>
            </Card>
        </div>
    );
};

export default UserAddressChanges;
