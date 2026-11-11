// A regression guard for the /admin hub page. It
// locks down the page's groupTools logic, how external links render, and
// the javascript: URL guard.

import { beforeEach, describe, expect, it, vi } from "vitest";

import { renderV2, resetInertiaStubs, type InertiaStubs } from "app/frontend/__tests__/test-utils";

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown>; url: string }>(() => ({
        props: {} as Record<string, unknown>,
        url: "/admin",
    })),
    router: {
        visit: vi.fn<(url: string) => void>(),
        post: vi.fn<(url: string, data?: unknown) => void>(),
        put: vi.fn<(url: string, data?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown) => void>(),
        delete: vi.fn<(url: string) => void>(),
        get: vi.fn<(url: string) => void>(),
        reload: vi.fn<(opts?: Record<string, unknown>) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: inertia.usePage,
        router: inertia.router,
        Link: ({ children, href, ...rest }: { children: unknown; href: string; [key: string]: unknown }) => (
            <a href={href} data-inertia-link {...(rest as Record<string, unknown>)}>
                {children as React.ReactNode}
            </a>
        ),
    };
});

import Index from "app/frontend/pages/admin/Index";

type Tool = {
    id: string;
    label: string;
    description: string;
    path: string;
    group: string;
    external: boolean;
};

const makeTool = (overrides: Partial<Tool> = {}): Tool => ({
    id: overrides.id ?? "bill_creator",
    label: overrides.label ?? "Bill Creator",
    description: overrides.description ?? "Create / edit bills",
    path: overrides.path ?? "/admin/bill_creator/new",
    group: overrides.group ?? "Content",
    external: overrides.external ?? false,
});

beforeEach(() => {
    resetInertiaStubs(inertia);
});

describe("admin/Index — grouping + rendering", () => {
    it("renders the page heading and lede copy", () => {
        const { queryByText } = renderV2(<Index tools={[]} />);
        expect(queryByText("Admin")).not.toBeNull();
        expect(queryByText(/Tools for managing Sway content/i)).not.toBeNull();
    });

    it("renders no section <h2>s when tools is empty", () => {
        const { container } = renderV2(<Index tools={[]} />);
        expect(container.querySelectorAll("section h2").length).toBe(0);
    });

    it("groups two tools in the same group under one heading", () => {
        const tools: Tool[] = [
            makeTool({ id: "a", label: "Tool A", group: "Settings" }),
            makeTool({ id: "b", label: "Tool B", group: "Settings" }),
        ];
        const { container, queryByText } = renderV2(<Index tools={tools} />);
        const settingsHeadings = Array.from(container.querySelectorAll("section h2")).filter(
            (h) => h.textContent === "Settings",
        );
        expect(settingsHeadings.length).toBe(1);
        expect(queryByText("Tool A")).not.toBeNull();
        expect(queryByText("Tool B")).not.toBeNull();
    });

    it("orders groups by GROUP_ORDER (Content, Settings, Data) regardless of input order", () => {
        const tools: Tool[] = [
            makeTool({ id: "d", group: "Data", label: "Data tool" }),
            makeTool({ id: "s", group: "Settings", label: "Settings tool" }),
            makeTool({ id: "c", group: "Content", label: "Content tool" }),
        ];
        const { container } = renderV2(<Index tools={tools} />);
        const headings = Array.from(container.querySelectorAll("section h2")).map((h) => h.textContent);
        expect(headings).toEqual(["Content", "Settings", "Data"]);
    });

    it("places unknown groups after the known ones, preserving input order", () => {
        const tools: Tool[] = [
            makeTool({ id: "c", group: "Content", label: "C" }),
            makeTool({ id: "x", group: "Experiments", label: "X" }),
            makeTool({ id: "z", group: "Zebras", label: "Z" }),
        ];
        const { container } = renderV2(<Index tools={tools} />);
        const headings = Array.from(container.querySelectorAll("section h2")).map((h) => h.textContent);
        expect(headings).toEqual(["Content", "Experiments", "Zebras"]);
    });

    it("renders an internal tool as an Inertia <Link>", () => {
        const tools: Tool[] = [makeTool({ external: false })];
        const { container } = renderV2(<Index tools={tools} />);
        const anchors = container.querySelectorAll("a[data-inertia-link]");
        expect(anchors.length).toBe(1);
    });

    it("renders a safe external tool as a target=_blank anchor with rel=noreferrer noopener", () => {
        const tools: Tool[] = [makeTool({ id: "monitor", path: "https://grafana.example.com/d/api", external: true })];
        const { container } = renderV2(<Index tools={tools} />);
        const externalAnchor = container.querySelector('a[target="_blank"]');
        expect(externalAnchor).not.toBeNull();
        expect(externalAnchor?.getAttribute("rel")).toContain("noreferrer");
        expect(externalAnchor?.getAttribute("rel")).toContain("noopener");
        expect(externalAnchor?.getAttribute("href")).toBe("https://grafana.example.com/d/api");
    });

    it("drops the entire entry when an 'external' tool ships with javascript: URL (F-i2-WR-001)", () => {
        const tools: Tool[] = [makeTool({ id: "evil", path: "javascript:alert('x')", external: true })];
        const { container } = renderV2(<Index tools={tools} />);
        // The unsafe URL must NOT reach the DOM in ANY anchor — Inertia's
        // left-click intercept doesn't cover middle-click or Ctrl-click
        // "Open in new tab", which would run the javascript: URL. The fix
        // returns null so no anchor renders at all for the offending tool.
        expect(container.querySelector('a[target="_blank"]')).toBeNull();
        const anchors = Array.from(container.querySelectorAll("a"));
        expect(anchors.some((a) => a.getAttribute("href")?.toLowerCase().startsWith("javascript:"))).toBe(false);
    });

    it("drops a tool with null/empty path entirely (F-i2-IN-001)", () => {
        // Mirror the case where a future controller branch emits {path: nil}
        // — TypeScript says `path: string` but a Ruby-side nil flows through
        // as an empty string in worst case. The guard rejects both.
        const tools: Tool[] = [makeTool({ id: "nullish", path: "", external: true })];
        const { container } = renderV2(<Index tools={tools} />);
        expect(container.querySelector('a[target="_blank"]')).toBeNull();
    });

    it("hides a group section whose tools all fail the safe-href guard (F-i3-IN-001)", () => {
        // ToolCard returns null for unsafe URLs. If a whole group consists of
        // only unsafe tools, the section heading would otherwise render with
        // an empty grid below it — a confusing empty spot on the page.
        const tools: Tool[] = [makeTool({ id: "evil", path: "javascript:x", group: "Data", external: true })];
        const { container, queryByText } = renderV2(<Index tools={tools} />);
        // No "Data" heading at all — section hidden entirely.
        expect(queryByText("Data")).toBeNull();
        // No empty <section> wrapper either.
        expect(container.querySelectorAll("section").length).toBe(0);
    });

    it("renders only renderable tools when a group mixes safe + unsafe (F-i3-IN-001)", () => {
        const tools: Tool[] = [
            makeTool({ id: "safe", path: "/admin/llm_settings", group: "Settings", external: false, label: "Safe" }),
            makeTool({ id: "evil", path: "javascript:x", group: "Settings", external: true, label: "Evil" }),
        ];
        const { container, queryByText } = renderV2(<Index tools={tools} />);
        expect(queryByText("Settings")).not.toBeNull();
        expect(queryByText("Safe")).not.toBeNull();
        // The unsafe sibling shouldn't render any anchor or label.
        expect(queryByText("Evil")).toBeNull();
        const anchors = Array.from(container.querySelectorAll("a"));
        expect(anchors.some((a) => a.getAttribute("href")?.toLowerCase().startsWith("javascript:"))).toBe(false);
    });

    it("renders the Database & Queue Telemetry card when database_health is provided", () => {
        const { queryByText } = renderV2(
            <Index
                tools={[]}
                database_health={{
                    databases: [{ name: "primary", database_bytes: 2048, wal_bytes: 512 }],
                    solid_queue_ready: 3,
                    solid_queue_failed: 1,
                }}
            />,
        );
        expect(queryByText("SQLite & Solid Queue Snapshot")).not.toBeNull();
        expect(queryByText("primary")).not.toBeNull();
        expect(queryByText(/DB: 2\.0 KB · WAL: 512 B/)).not.toBeNull();
    });
});
