// @lat: [[mobile-markdown-rendering#Rendering]]
import React, { useMemo } from "react";
import { Linking, Platform, Text, View } from "react-native";
import type { Definition, Nodes, PhrasingContent, Root, RootContent, Table } from "mdast";
import { isSafeCitationUrl } from "../utils/safeUrl";
import { parseMarkdown, truncateMarkdown, visibleText } from "../utils/markdownTree";

export interface MarkdownProps {
    content?: string | null;
    maxChars?: number;
    expanded?: boolean;
    testID?: string;
    className?: string;
    linkClassName?: string;
    selectable?: boolean;
    onOpenUrl?: (url: string) => void | Promise<void>;
}

const MONO = Platform.select({ ios: "Menlo", default: "monospace" });
const HEADING_SIZES = ["text-xl", "text-lg", "text-base", "text-base", "text-sm", "text-sm"];
const DEFAULT_LINK_CLASS = "text-accent-light dark:text-accent-dark font-open-sans-semibold underline";

export function markdownExceedsLimit(content: string | null | undefined, maxChars: number): boolean {
    return content ? truncateMarkdown(parseMarkdown(content), maxChars).isTruncated : false;
}

function collectDefinitions(root: Root): Map<string, string> {
    const urls = new Map<string, string>();
    const visit = (node: Nodes) => {
        if (node.type === "definition") {
            const def = node as Definition;
            if (!urls.has(def.identifier)) urls.set(def.identifier, def.url);
        }
        if ("children" in node) (node.children as Nodes[]).forEach(visit);
    };
    visit(root);
    return urls;
}

export function Markdown({
    content,
    maxChars,
    expanded,
    testID,
    className = "",
    linkClassName = DEFAULT_LINK_CLASS,
    selectable,
    onOpenUrl,
}: MarkdownProps) {
    const parsed = useMemo(() => (content ? parseMarkdown(content) : null), [content]);
    const definitions = useMemo(() => (parsed ? collectDefinitions(parsed) : new Map<string, string>()), [parsed]);
    if (!parsed) return null;

    const shouldTruncate = typeof maxChars === "number" && !expanded;
    const { tree, isTruncated } = shouldTruncate
        ? truncateMarkdown(parsed, maxChars)
        : { tree: parsed, isTruncated: false };
    const blocks = tree.children.filter((n) => n.type !== "definition");
    if (blocks.length === 0) return null;

    const openUrl = (url: string) => {
        if (!isSafeCitationUrl(url)) return;
        if (onOpenUrl) {
            void onOpenUrl(url);
            return;
        }
        void Linking.openURL(url).catch(() => {});
    };

    const renderLink = (key: number, url: string | undefined, children: PhrasingContent[]) => {
        const label = children.map(visibleText).join("");
        if (!label) return null;
        if (!url || !isSafeCitationUrl(url)) return <React.Fragment key={key}>{renderInline(children)}</React.Fragment>;
        return (
            <Text
                key={key}
                accessibilityRole="link"
                accessibilityLabel={label}
                accessibilityHint="Opens link in browser"
                className={linkClassName}
                onPress={() => openUrl(url)}
            >
                {renderInline(children)}
            </Text>
        );
    };

    const renderInline = (nodes: PhrasingContent[]): React.ReactNode =>
        nodes.map((node, i) => {
            switch (node.type) {
                case "text":
                    return <React.Fragment key={i}>{node.value}</React.Fragment>;
                case "strong":
                    return (
                        <Text key={i} className="font-open-sans-semibold">
                            {renderInline(node.children)}
                        </Text>
                    );
                case "emphasis":
                    return (
                        <Text key={i} className="italic">
                            {renderInline(node.children)}
                        </Text>
                    );
                case "delete":
                    return (
                        <Text key={i} className="line-through">
                            {renderInline(node.children)}
                        </Text>
                    );
                case "inlineCode":
                    return (
                        <Text key={i} style={{ fontFamily: MONO }}>
                            {node.value}
                        </Text>
                    );
                case "break":
                    return <React.Fragment key={i}>{"\n"}</React.Fragment>;
                case "link":
                    return renderLink(i, node.url, node.children);
                case "linkReference":
                    return renderLink(i, definitions.get(node.identifier), node.children);
                case "image":
                    return <React.Fragment key={i}>{node.alt}</React.Fragment>;
                case "imageReference":
                    return <React.Fragment key={i}>{node.alt}</React.Fragment>;
                case "footnoteReference":
                    return <React.Fragment key={i}>{`[${node.label ?? node.identifier}]`}</React.Fragment>;
                case "html":
                    return <React.Fragment key={i}>{node.value}</React.Fragment>;
                default:
                    return null;
            }
        });

    const renderTable = (key: number, table: Table) => (
        <View key={key} className="border border-border-light dark:border-border-dark rounded-lg overflow-hidden">
            {table.children.map((row, r) => (
                <View
                    key={r}
                    className={`flex-row ${r === 0 ? "bg-surface-2-light dark:bg-surface-2-dark" : "border-t border-border-light dark:border-border-dark"}`}
                >
                    {row.children.map((cell, c) => (
                        <View key={c} className="flex-1 px-2 py-1">
                            <Text
                                className={`${className} ${r === 0 ? "font-open-sans-semibold" : ""}`}
                                style={{ textAlign: table.align?.[c] ?? "left" }}
                            >
                                {renderInline(cell.children)}
                            </Text>
                        </View>
                    ))}
                </View>
            ))}
        </View>
    );

    const renderBlocks = (nodes: RootContent[]): React.ReactNode =>
        nodes.map((node, i) => {
            switch (node.type) {
                case "paragraph":
                    return (
                        <Text key={i} className={className} selectable={selectable}>
                            {renderInline(node.children)}
                        </Text>
                    );
                case "heading":
                    return (
                        <Text
                            key={i}
                            accessibilityRole="header"
                            className={`${className} ${HEADING_SIZES[node.depth - 1]} font-open-sans-semibold`}
                            selectable={selectable}
                        >
                            {renderInline(node.children)}
                        </Text>
                    );
                case "list":
                    return (
                        <View key={i} className="gap-1">
                            {node.children.map((item, n) => (
                                <View key={n} className="flex-row gap-2">
                                    <Text className={className}>
                                        {typeof item.checked === "boolean"
                                            ? item.checked
                                                ? "☑"
                                                : "☐"
                                            : node.ordered
                                              ? `${(node.start ?? 1) + n}.`
                                              : "•"}
                                    </Text>
                                    <View className="flex-1 gap-1">{renderBlocks(item.children)}</View>
                                </View>
                            ))}
                        </View>
                    );
                case "blockquote":
                    return (
                        <View
                            key={i}
                            className="border-l-4 border-border-strong-light dark:border-border-strong-dark pl-3 gap-1"
                        >
                            {renderBlocks(node.children)}
                        </View>
                    );
                case "code":
                    return (
                        <View key={i} className="bg-surface-2-light dark:bg-surface-2-dark rounded-lg p-2">
                            <Text className={className} style={{ fontFamily: MONO }}>
                                {node.value}
                            </Text>
                        </View>
                    );
                case "thematicBreak":
                    return <View key={i} className="h-px bg-border-light dark:bg-border-dark" />;
                case "table":
                    return renderTable(i, node);
                case "footnoteDefinition":
                    return (
                        <View key={i} className="flex-row gap-2">
                            <Text className={className}>{`[${node.label ?? node.identifier}]`}</Text>
                            <View className="flex-1 gap-1">{renderBlocks(node.children)}</View>
                        </View>
                    );
                case "html":
                    return (
                        <Text key={i} className={className}>
                            {node.value}
                        </Text>
                    );
                default:
                    return null;
            }
        });

    return (
        <View testID={testID} className="gap-2">
            {renderBlocks(blocks)}
            {isTruncated ? <Text className={className}>…</Text> : null}
        </View>
    );
}

export default Markdown;
