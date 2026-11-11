import { Head } from "@inertiajs/react";
import { sway } from "sway";

// @lat: [[oss-licenses-page-scope#Why the /licenses page lists what it does]]

interface IProps {
    licenses: sway.IOssDependency[];
}

const Licenses: React.FC<IProps> = ({ licenses }) => {
    return (
        <>
            <Head title="Open-source licenses" />
            <section className="mx-auto w-full max-w-2xl">
                <h1 className="text-2xl font-black text-foreground">Open-source licenses</h1>
                <p className="mt-1 text-sm text-muted-foreground">
                    Third-party packages bundled into Sway's frontend that carry a license other than MIT. Most
                    dependencies are MIT-licensed and aren't listed here.
                </p>

                <section className="mt-8">
                    <h2 className="text-lg font-black text-foreground">
                        Packages <span className="font-semibold text-muted-foreground">({licenses.length})</span>
                    </h2>

                    {licenses.length === 0 ? (
                        <p className="mt-2 text-sm text-muted-foreground">
                            No data available for this build. Run{" "}
                            <span className="font-mono">rake sway:licenses:frontend</span> to generate it locally.
                        </p>
                    ) : (
                        <ul className="mt-3 border-t-neo border-border">
                            {licenses.map((dep) => (
                                <li
                                    key={dep.name}
                                    className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b-neo border-border py-2"
                                >
                                    <span className="min-w-0">
                                        {dep.homepage && /^https?:\/\//i.test(dep.homepage) ? (
                                            <a
                                                href={dep.homepage}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="font-semibold text-foreground underline-offset-4 hover:underline"
                                            >
                                                {dep.name}
                                            </a>
                                        ) : (
                                            <span className="font-semibold text-foreground">{dep.name}</span>
                                        )}
                                        <span className="ml-2 font-mono text-xs text-muted-foreground">
                                            {dep.version}
                                        </span>
                                    </span>
                                    <span className="text-xs font-semibold text-muted-foreground">{dep.license}</span>
                                </li>
                            ))}
                        </ul>
                    )}
                </section>
            </section>
        </>
    );
};

export default Licenses;
