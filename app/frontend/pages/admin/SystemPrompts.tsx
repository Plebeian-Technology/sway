import { Link } from "@inertiajs/react";
import * as React from "react";

import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "app/frontend/components/ui/accordion";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Separator } from "app/frontend/components/ui/separator";
import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IPromptEntry {
    id: string;
    label: string;
    purpose: string;
    builder: string;
    model: string;
    model_setting_label: string;
    system_prompt: string | null;
    character_count: number | null;
    unavailable_reason: string | null;
    sway_locale_name?: string | null;
}

interface IProps {
    models: {
        summarization: string;
        classification: string;
    };
    active_category_count: number;
    llm_settings_path: string;
    prompts: IPromptEntry[];
}

const ModelRow: React.FC<{ label: string; model: string }> = ({ label, model }) => (
    <div className="flex flex-wrap items-baseline justify-between gap-2 py-2">
        <span className="text-sm text-foreground">{label}</span>
        <span className="font-mono text-sm text-muted-foreground">{model}</span>
    </div>
);

const PromptItem: React.FC<{ entry: IPromptEntry }> = ({ entry }) => {
    const prompt = entry.system_prompt;

    return (
        <AccordionItem value={entry.id}>
            <AccordionTrigger>
                <span className="flex flex-wrap items-center gap-3">
                    <span>{entry.label}</span>
                    {entry.sway_locale_name && (
                        <Badge data-testid={`system-prompt-locale-${entry.id}`}>{entry.sway_locale_name}</Badge>
                    )}
                    {prompt === null ? (
                        <Badge variant="outline">Not sent</Badge>
                    ) : (
                        <Badge variant="outline">
                            {`${(entry.character_count ?? prompt.length).toLocaleString()} characters`}
                        </Badge>
                    )}
                </span>
            </AccordionTrigger>
            <AccordionContent>
                <div className="space-y-3">
                    <p className="text-sm text-muted-foreground">{entry.purpose}</p>
                    <div className="font-mono text-xs text-muted-foreground">
                        <div>Builder: {entry.builder}</div>
                        <div>
                            Model: {entry.model} ({entry.model_setting_label})
                        </div>
                    </div>
                    {prompt === null ? (
                        <Alert variant="warning" data-testid={`system-prompt-unavailable-${entry.id}`}>
                            <AlertTitle className="line-clamp-none">This prompt is not sent</AlertTitle>
                            <AlertDescription>{entry.unavailable_reason}</AlertDescription>
                        </Alert>
                    ) : (
                        <pre
                            className="overflow-x-auto rounded-md bg-secondary p-3 font-mono text-xs"
                            data-testid={`system-prompt-${entry.id}`}
                        >
                            {prompt}
                        </pre>
                    )}
                </div>
            </AccordionContent>
        </AccordionItem>
    );
};

const SystemPrompts: React.FC<IProps> = ({ models, active_category_count, llm_settings_path, prompts }) => {
    const [open, setOpen] = React.useState<string[]>([]);
    const allOpen = prompts.length > 0 && open.length === prompts.length;

    const toggleAll = () => {
        setOpen(allOpen ? [] : prompts.map((entry) => entry.id));
    };

    return (
        <div className="mx-auto w-full max-w-4xl space-y-8">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">System prompts</h1>
                {/* @lat: [[admin-system-prompts-page#Why the standing instruction is the half worth showing]] */}
                <p className="text-sm text-muted-foreground">
                    This is the standing instruction half of each call, and nothing else. Every real call also carries a
                    user message holding that call's own bill text, testimony or attachments, and none of that appears
                    here. These prompts are read-only: they change by a code change and a deploy. They are rendered now
                    by the same builder classes the jobs use, against this installation's live active-category list.
                </p>
            </div>

            <Card data-testid="system-prompts-models">
                <CardHeader>
                    <CardTitle>Models</CardTitle>
                </CardHeader>
                <CardContent>
                    <ModelRow label="Summarization model" model={models.summarization} />
                    <Separator />
                    <ModelRow label="Testimony classification model" model={models.classification} />
                    <p className="pt-3 text-sm text-muted-foreground">
                        <Link href={llm_settings_path} className="underline underline-offset-4">
                            Change these models on LLM Settings
                        </Link>
                    </p>
                </CardContent>
            </Card>

            {active_category_count === 0 ? (
                <Alert variant="warning" data-testid="system-prompts-empty-taxonomy">
                    <AlertTitle className="line-clamp-none">No active categories</AlertTitle>
                    <AlertDescription>
                        Two of these prompts name the active taxonomy. With none active, the categorisation call is
                        never made and the summary prompt asks for no categories at all.
                    </AlertDescription>
                </Alert>
            ) : (
                <p className="text-sm text-muted-foreground" data-testid="system-prompts-taxonomy">
                    {`The bill summary and bill categories prompts name ${countNoun(
                        active_category_count,
                        "active category",
                        "active categories",
                    )}. The other three do not.`}
                </p>
            )}

            <section className="space-y-2" aria-labelledby="system-prompts-list">
                <h2 id="system-prompts-list" className="sr-only">
                    Prompts
                </h2>
                <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={toggleAll}
                    data-testid="btn-toggle-all-system-prompts"
                >
                    {allOpen ? "Collapse all" : "Expand all"}
                </Button>

                <Accordion type="multiple" value={open} onValueChange={setOpen}>
                    {prompts.map((entry) => (
                        <PromptItem key={entry.id} entry={entry} />
                    ))}
                </Accordion>
            </section>
        </div>
    );
};

export default SystemPrompts;
