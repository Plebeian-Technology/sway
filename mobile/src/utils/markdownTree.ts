// @lat: [[mobile-markdown-rendering#Parsing and truncation]]
import type { Nodes, Parents, Root } from "mdast";
import { fromMarkdown } from "mdast-util-from-markdown";
import { gfmFromMarkdown } from "mdast-util-gfm";
import { gfm } from "micromark-extension-gfm";

export const MAX_MARKDOWN_CACHE_ENTRIES = 100;

const markdownCache = new Map<string, Root>();

export function clearMarkdownCache(): void {
    markdownCache.clear();
}

export function parseMarkdown(content: string): Root {
    const cached = markdownCache.get(content);
    if (cached) {
        markdownCache.delete(content);
        markdownCache.set(content, cached);
        return cached;
    }

    const text = content.replace(/NEWLINE|ENDING/g, " ");
    const root = fromMarkdown(text, { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] });

    if (markdownCache.size >= MAX_MARKDOWN_CACHE_ENTRIES) {
        const oldestKey = markdownCache.keys().next().value;
        if (oldestKey !== undefined) {
            markdownCache.delete(oldestKey);
        }
    }

    markdownCache.set(content, root);
    return root;
}

export function visibleText(node: Nodes): string {
    if ("children" in node) return node.children.map(visibleText).join("");
    if (node.type === "image" || node.type === "imageReference") return node.alt ?? "";
    if (node.type === "footnoteReference") return `[${node.label ?? node.identifier}]`;
    if (node.type === "break") return "\n";
    if ("value" in node) return node.value;
    return "";
}

export function markdownVisibleLength(root: Root): number {
    return visibleText(root).length;
}

const ATOMIC_TYPES = new Set([
    "link",
    "linkReference",
    "inlineCode",
    "code",
    "table",
    "image",
    "imageReference",
    "footnoteReference",
]);

interface Budget {
    left: number;
    cut: boolean;
}

function trim(node: Nodes, budget: Budget): Nodes | null {
    if (node.type === "definition") return null;

    const text = visibleText(node);

    if (ATOMIC_TYPES.has(node.type) || !("children" in node)) {
        if (
            (node.type === "link" ||
                node.type === "linkReference" ||
                node.type === "image" ||
                node.type === "imageReference") &&
            !text
        ) {
            return null;
        }
        if (budget.left <= 0) {
            if (node.type === "break") return null;
            budget.cut = true;
            return null;
        }
        if (!text && !ATOMIC_TYPES.has(node.type)) return node;
        if (ATOMIC_TYPES.has(node.type) || text.length <= budget.left) {
            budget.left -= text.length;
            return node;
        }
        const kept = text.slice(0, budget.left);
        budget.left = 0;
        budget.cut = true;
        return { ...node, value: kept } as Nodes;
    }

    const children: Nodes[] = [];
    for (const child of node.children as Nodes[]) {
        if (budget.cut) break;
        const kept = trim(child, budget);
        if (kept) children.push(kept);
    }
    if (children.length === 0) return null;
    return { ...node, children } as Parents;
}

export function truncateMarkdown(root: Root, maxChars: number): { tree: Root; isTruncated: boolean } {
    const budget: Budget = { left: maxChars, cut: false };
    const tree = (trim(root, budget) as Root | null) ?? { ...root, children: [] };
    return { tree, isTruncated: budget.cut };
}
