import { useForm } from "@inertiajs/react";
import { useState } from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";

interface NewsSource {
    url: string;
    path_policy: "search_hint" | "restrict";
}

interface SummarizationInstructionData {
    id: number;
    sway_locale_id: number;
    news_media_website_urls: string[];
    legislative_body_makeup: string | null;
    last_seeded_at: string | null;
    updated_at: string | null;
}

interface LocaleRow {
    id: number;
    label: string;
    user_count: number;
    sample_street: string | null;
    sample_postal_code: string | null;
    sample_latitude: number | null;
    sample_longitude: number | null;
    summarization_instruction?: SummarizationInstructionData | null;
    news_sources?: NewsSource[];
}

interface Tier {
    key: string;
    label: string;
    locales: LocaleRow[];
}

interface IProps {
    tiers: Tier[];
}

type SampleAddressForm = {
    sway_locale: {
        sample_street: string;
        sample_postal_code: string;
        sample_latitude: string;
        sample_longitude: string;
    };
};

const pluralize = (count: number, noun: string) => `${count} ${noun}${count === 1 ? "" : "s"}`;

const asText = (value: string | number | null) => (value === null ? "" : String(value));

const hasSampleAddress = (row: LocaleRow) =>
    row.sample_street !== null &&
    row.sample_postal_code !== null &&
    row.sample_latitude !== null &&
    row.sample_longitude !== null;

// @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
const SampleAddressFields: React.FC<{ row: LocaleRow }> = ({ row }) => {
    const form = useForm<SampleAddressForm>({
        sway_locale: {
            sample_street: asText(row.sample_street),
            sample_postal_code: asText(row.sample_postal_code),
            sample_latitude: asText(row.sample_latitude),
            sample_longitude: asText(row.sample_longitude),
        },
    });

    const handleSubmit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        form.patch(`/admin/locales/${row.id}`, { preserveScroll: true });
    };

    const fields = [
        { name: "sample_street" as const, label: "Street" },
        { name: "sample_postal_code" as const, label: "Postal code" },
        { name: "sample_latitude" as const, label: "Latitude" },
        { name: "sample_longitude" as const, label: "Longitude" },
    ];

    return (
        <form onSubmit={handleSubmit} className="mt-2 space-y-3 rounded-md border border-border bg-muted/40 p-4">
            <p className="text-sm text-muted-foreground">
                The address a stand-in development account signs in with. Empty on every locale but the demo one.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
                {fields.map((field) => (
                    <div key={field.name} className="space-y-1">
                        <Label htmlFor={`locale-${row.id}-${field.name}`}>{field.label}</Label>
                        <Input
                            id={`locale-${row.id}-${field.name}`}
                            value={form.data.sway_locale[field.name]}
                            onChange={(e) => form.setData(`sway_locale.${field.name}`, e.target.value)}
                            disabled={form.processing}
                        />
                    </div>
                ))}
            </div>
            <Button type="submit" size="sm" disabled={form.processing}>
                {form.processing ? "Saving..." : "Save sample address"}
            </Button>
        </form>
    );
};

// @lat: [[news-source-ui#Read-only presentation in administrative surfaces]]
const SummarizationFields: React.FC<{ row: LocaleRow }> = ({ row }) => {
    const sources: NewsSource[] =
        row.news_sources ??
        row.summarization_instruction?.news_media_website_urls.map((url) => ({
            url,
            path_policy: "search_hint" as const,
        })) ??
        [];

    return (
        <div className="mt-2 space-y-4 rounded-md border border-border bg-muted/40 p-3 sm:p-4">
            <div className="space-y-2 rounded-md border border-border/50 bg-background/50 p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                    <Label className="text-xs font-medium text-foreground">Newsroom sources</Label>
                    <Badge variant="outline" className="whitespace-normal text-left">
                        Authoritative · Locale configuration
                    </Badge>
                </div>
                <p className="text-xs text-muted-foreground">
                    Trusted local newsroom websites used to search and cite reporting for bill summaries. Newsroom
                    sources are configured in the locale's configuration file (config/sway_locales/*.yml) and
                    version-controlled. They cannot be edited in the browser; updating sources requires a code change
                    and deploy.
                </p>
                {sources.length > 0 ? (
                    <div className="divide-y divide-border/60 rounded-md border border-border/50 bg-background/50">
                        {sources.map((source, index) => (
                            <div
                                key={`${source.url}-${index}`}
                                className="flex flex-col gap-1.5 p-2.5 sm:flex-row sm:items-center sm:justify-between"
                            >
                                <span className="font-mono text-xs break-all select-all text-foreground">
                                    {source.url}
                                </span>
                                <div className="flex shrink-0 items-center gap-1.5 self-start sm:self-auto">
                                    <Badge
                                        variant={source.path_policy === "restrict" ? "solid" : "outline"}
                                        className="font-mono text-[10px]"
                                    >
                                        {source.path_policy === "restrict" ? "Restricted path" : "Search hint"}
                                    </Badge>
                                </div>
                            </div>
                        ))}
                    </div>
                ) : (
                    <p className="text-xs italic text-muted-foreground">
                        No newsroom sources configured for this jurisdiction. News discovery is disabled.
                    </p>
                )}
            </div>

            <div className="space-y-2 rounded-md border border-border/50 bg-background/50 p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                    <Label className="text-xs font-medium text-foreground">Legislative body makeup</Label>
                    <Badge variant="outline" className="whitespace-normal text-left">
                        Immutable · Prompt defense
                    </Badge>
                </div>
                <p className="text-xs text-muted-foreground">
                    Procedural rules, chamber thresholds, and veto override rules passed to the LLM system prompt. This
                    text is immutable in code to defend against prompt injection; changes require an audited code change
                    and application deploy.
                </p>
                {row.summarization_instruction?.legislative_body_makeup ? (
                    <pre className="overflow-x-auto whitespace-pre-wrap wrap-break-word rounded-md border border-border/40 bg-muted/60 p-3 font-mono text-xs text-foreground/80">
                        {row.summarization_instruction.legislative_body_makeup}
                    </pre>
                ) : (
                    <p className="text-xs italic text-muted-foreground">
                        No legislative body description declared for this jurisdiction.
                    </p>
                )}
            </div>
        </div>
    );
};

const LocaleBarRow: React.FC<{ row: LocaleRow; max: number }> = ({ row, max }) => {
    const [isEditing, setIsEditing] = useState(false);
    const [isEditingSummarization, setIsEditingSummarization] = useState(false);
    const width = max > 0 ? Math.max((row.user_count / max) * 100, row.user_count > 0 ? 2 : 0) : 0;

    return (
        <li className="py-1.5">
            {/* @lat: [[tab-strips-at-narrow-viewports#What the four standalone admin pages measure]] */}
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">
                <span className="min-w-0 truncate text-sm text-foreground sm:w-44 sm:shrink-0" title={row.label}>
                    {row.label}
                </span>
                <div
                    className="h-2 w-full overflow-hidden rounded-full bg-muted sm:w-auto sm:flex-1"
                    aria-hidden="true"
                >
                    <div className="h-full rounded-full bg-primary transition-[width]" style={{ width: `${width}%` }} />
                </div>
                <div className="flex items-center justify-between gap-3 sm:contents">
                    <span className="text-sm font-semibold tabular-nums text-foreground sm:w-12 sm:shrink-0 sm:text-right">
                        {row.user_count.toLocaleString()}
                    </span>
                    <div className="flex flex-wrap items-center gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            aria-expanded={isEditing}
                            aria-controls={`locale-${row.id}-sample-address`}
                            onClick={() => setIsEditing((open) => !open)}
                        >
                            {hasSampleAddress(row) ? "Sample address" : "Add sample address"}
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            aria-expanded={isEditingSummarization}
                            aria-controls={`locale-${row.id}-summarization`}
                            onClick={() => setIsEditingSummarization((open) => !open)}
                        >
                            Summarization
                        </Button>
                    </div>
                </div>
            </div>
            <div id={`locale-${row.id}-sample-address`} hidden={!isEditing}>
                {isEditing ? <SampleAddressFields row={row} /> : null}
            </div>
            <div id={`locale-${row.id}-summarization`} hidden={!isEditingSummarization}>
                {isEditingSummarization ? <SummarizationFields row={row} /> : null}
            </div>
        </li>
    );
};

const TierCard: React.FC<{ tier: Tier }> = ({ tier }) => {
    const max = tier.locales.reduce((acc, row) => Math.max(acc, row.user_count), 0);

    return (
        <Card>
            <CardHeader>
                <CardTitle className="flex items-baseline justify-between gap-4 text-lg">
                    <span>{tier.label}</span>
                    <span className="text-sm font-normal text-muted-foreground">
                        {pluralize(tier.locales.length, "locale")}
                    </span>
                </CardTitle>
            </CardHeader>
            <CardContent>
                {tier.locales.length === 0 ? (
                    <p className="text-sm text-muted-foreground">No locales yet.</p>
                ) : (
                    <ul>
                        {tier.locales.map((row) => (
                            <LocaleBarRow key={row.id} row={row} max={max} />
                        ))}
                    </ul>
                )}
            </CardContent>
        </Card>
    );
};

const Locales: React.FC<IProps> = ({ tiers }) => {
    return (
        <div className="mx-auto w-full max-w-3xl space-y-8">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">Locales</h1>
                <p className="text-sm text-muted-foreground">
                    Registered users per locale. City and state locales are created automatically from each user's
                    address, so this is every place Sway has a registration — not only the supported ones.
                </p>
            </div>

            <div className="space-y-6">
                {tiers.map((tier) => (
                    <TierCard key={tier.key} tier={tier} />
                ))}
            </div>
        </div>
    );
};

export default Locales;
