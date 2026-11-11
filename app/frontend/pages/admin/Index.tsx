// @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]

import { Link } from "@inertiajs/react";
import { useMemo } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { isSafeExternalHref } from "app/frontend/sway_utils/safeHref";

type Tool = {
    id: string;
    label: string;
    description: string;
    path: string;
    group: string;
    external: boolean;
};

type DatabaseFileHealth = {
    name: string;
    database_bytes: number;
    wal_bytes: number;
};

type DatabaseHealth = {
    databases: DatabaseFileHealth[];
    solid_queue_ready: number;
    solid_queue_failed: number;
};

interface IProps {
    tools: Tool[];
    database_health?: DatabaseHealth;
}

const formatBytes = (bytes: number): string => {
    if (!Number.isFinite(bytes) || bytes <= 0) {
        return "0 B";
    }
    const units = ["B", "KB", "MB", "GB"];
    const exp = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const value = bytes / 1024 ** exp;
    return `${exp === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[exp]}`;
};

// @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]
const GROUP_ORDER = ["Content", "Settings", "Data"];

const groupTools = (tools: Tool[]): Array<[string, Tool[]]> => {
    const buckets = new Map<string, Tool[]>();
    for (const tool of tools) {
        const bucket = buckets.get(tool.group) ?? [];
        bucket.push(tool);
        buckets.set(tool.group, bucket);
    }
    const ordered: Array<[string, Tool[]]> = [];
    for (const group of GROUP_ORDER) {
        if (buckets.has(group)) {
            ordered.push([group, buckets.get(group)!]);
            buckets.delete(group);
        }
    }
    for (const [group, bucket] of buckets) {
        ordered.push([group, bucket]);
    }
    return ordered;
};

// @lat: [[safe-external-href-check#Why isSafeExternalHref exists]]

const ToolCard = ({ tool }: { tool: Tool }) => {
    const inner = (
        <Card className="h-full transition-[transform,box-shadow] hover:-translate-y-[1px]">
            <CardHeader>
                <CardTitle className="text-lg">{tool.label}</CardTitle>
                <CardDescription>{tool.description}</CardDescription>
            </CardHeader>
            <CardContent>
                <span className="text-sm font-medium text-foreground/70">{tool.path} →</span>
            </CardContent>
        </Card>
    );

    if (tool.external) {
        // @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]
        if (!isSafeExternalHref(tool.path)) {
            return null;
        }
        return (
            <a
                href={tool.path}
                target="_blank"
                rel="noreferrer noopener"
                className="block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-xl"
            >
                {inner}
            </a>
        );
    }

    return (
        <Link
            href={tool.path}
            className="block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-xl"
        >
            {inner}
        </Link>
    );
};

const Index: React.FC<IProps> = ({ tools, database_health }) => {
    // @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]
    const grouped = useMemo(() => groupTools(tools), [tools]);

    return (
        <div className="mx-auto w-full max-w-5xl space-y-8">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">Admin</h1>
                <p className="text-sm text-muted-foreground">
                    Tools for managing Sway content, settings, and operator state.
                </p>
            </div>

            {grouped.map(([group, bucket]) => {
                // @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]
                const renderable = bucket.filter((tool) => !tool.external || isSafeExternalHref(tool.path));
                if (renderable.length === 0) {
                    return null;
                }
                return (
                    <section key={group} className="space-y-3">
                        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">{group}</h2>
                        <div className="grid gap-4 sm:grid-cols-2">
                            {renderable.map((tool) => (
                                <ToolCard key={tool.id} tool={tool} />
                            ))}
                        </div>
                    </section>
                );
            })}

            {database_health && (
                <aside aria-label="Database and queue health" className="space-y-3">
                    <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                        Database &amp; Queue Telemetry
                    </h2>
                    <Card>
                        <CardHeader className="pb-2">
                            <CardTitle className="text-base">SQLite &amp; Solid Queue Snapshot</CardTitle>
                            <CardDescription>
                                Live SQLite DB/WAL file sizes and background job queue depth alongside Beszel host
                                metrics.
                            </CardDescription>
                        </CardHeader>
                        <CardContent className="space-y-4">
                            <div className="flex flex-wrap gap-6 text-sm">
                                <div>
                                    <span className="text-muted-foreground">Ready Jobs: </span>
                                    <span className="font-medium">{database_health.solid_queue_ready}</span>
                                </div>
                                <div>
                                    <span className="text-muted-foreground">Failed Jobs: </span>
                                    <span className="font-medium">{database_health.solid_queue_failed}</span>
                                </div>
                            </div>
                            <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-4">
                                {database_health.databases.map((db) => (
                                    <div key={db.name} className="rounded-lg border p-3 text-sm">
                                        <div className="font-medium capitalize">{db.name}</div>
                                        <div className="mt-1 text-xs text-muted-foreground">
                                            DB: {formatBytes(db.database_bytes)} · WAL: {formatBytes(db.wal_bytes)}
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </CardContent>
                    </Card>
                </aside>
            )}
        </div>
    );
};

export default Index;
