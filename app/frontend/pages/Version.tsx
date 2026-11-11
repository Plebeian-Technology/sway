import { Head, Link, usePage } from "@inertiajs/react";
import { ReactNode } from "react";
import { sway } from "sway";

import { formatDeployedAt, releaseLabel } from "app/frontend/sway_utils/release";

// @lat: [[release-git-fallback-and-caching#Why Version.tsx's "Built from" cell says what it says]]

const Row = ({ label, mono, children }: { label: string; mono?: boolean; children: ReactNode }) => (
    <div className="flex flex-col gap-1 border-b-neo border-border py-3 sm:flex-row sm:items-baseline sm:justify-between">
        <span className="text-sm font-semibold text-muted-foreground">{label}</span>
        <span className={mono ? "break-all font-mono text-sm text-foreground" : "text-sm text-foreground"}>
            {children}
        </span>
    </div>
);

const Version: React.FC = () => {
    const release = usePage<sway.IPageProps>().props.release;

    return (
        <>
            <Head title="Version" />
            <section className="mx-auto w-full max-w-xl">
                <h1 className="text-2xl font-black text-foreground">{releaseLabel(release)}</h1>
                <p className="mt-1 text-sm text-muted-foreground">The build currently running in production.</p>

                <div className="mt-6">
                    <Row label="Release">{release?.version ?? "—"}</Row>
                    <Row label="Deployed">{formatDeployedAt(release?.deployed_at)}</Row>
                    <Row label="Commit (this release)" mono>
                        {release?.sha ?? "unknown"}
                    </Row>
                    {/* @lat: [[release-git-fallback-and-caching#Why Version.tsx's "Built from" cell says what it says]] */}
                    <Row label="Built from">
                        {release?.built_from_committed_tree === false ? (
                            <span className="text-destructive">
                                the commit above plus uncommitted changes ({release.uncommitted_digest}) — rebuilding
                                from that commit gives a different app
                            </span>
                        ) : release?.built_from_committed_tree === true ? (
                            "exactly the commit above"
                        ) : (
                            // @lat: [[release-git-fallback-and-caching#Why Version.tsx's "Built from" cell says what it says]]
                            <span className="text-muted-foreground">
                                not recorded — this build did not come from a deploy
                            </span>
                        )}
                    </Row>
                    <Row label="Commit (previous release)" mono>
                        {release?.previous_sha ?? "—"}
                    </Row>
                </div>

                <p className="mt-6 text-sm">
                    <Link href="/licenses" className="font-semibold underline underline-offset-4">
                        Open-source licenses →
                    </Link>
                </p>
            </section>
        </>
    );
};

export default Version;
