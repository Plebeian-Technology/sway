// @lat: [[mobile-admin-area#The hub screen]]
import React from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";
import { DrawerActions, useNavigation } from "@react-navigation/native";

import BrandHeader from "../../components/BrandHeader";
import { EmptyState } from "../../components/ui/EmptyState";
import { ListRow } from "../../components/ui/ListRow";
import { useAdminHub, type AdminDatabaseHealth, type AdminTool } from "../../hooks/admin/useAdminHub";
import { adminToolScreens } from "./adminToolScreens";

interface NavLike {
    navigate: (screen: string, params?: Record<string, unknown>) => void;
}

interface Props {
    navigation: NavLike;
}

const NOT_ON_MOBILE_YET = "Not on mobile yet";
const GROUP_ORDER = ["Content", "Settings", "Data"];

const formatBytes = (bytes: number): string => {
    if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB"];
    const exp = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const value = bytes / 1024 ** exp;
    return `${exp === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[exp]}`;
};

const groupTools = (tools: AdminTool[]): [string, AdminTool[]][] => {
    const buckets = new Map<string, AdminTool[]>();
    for (const tool of tools) {
        buckets.set(tool.group, [...(buckets.get(tool.group) ?? []), tool]);
    }
    const known = GROUP_ORDER.filter((group) => buckets.has(group));
    const others = [...buckets.keys()].filter((group) => !GROUP_ORDER.includes(group));
    return [...known, ...others].map((group) => [group, buckets.get(group) ?? []]);
};

const GroupHeading = ({ title }: { title: string }) => (
    <Text
        accessibilityRole="header"
        className="px-4 pt-6 pb-2 text-sm font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark"
    >
        {title}
    </Text>
);

const DatabaseHealthList = ({ health }: { health: AdminDatabaseHealth }) => (
    <View testID="admin-database-health">
        <GroupHeading title="Database and queue" />
        {health.databases.map((db) => (
            <ListRow
                key={db.name}
                label={db.name}
                description={`DB: ${formatBytes(db.database_bytes)} · WAL: ${formatBytes(db.wal_bytes)}`}
            />
        ))}
        <ListRow
            label="Ready jobs"
            testID="admin-ready-jobs"
            rightSlot={
                <Text className="text-base text-foreground-light dark:text-foreground-dark">
                    {health.solid_queue_ready}
                </Text>
            }
        />
        <ListRow
            label="Failed jobs"
            testID="admin-failed-jobs"
            rightSlot={
                <Text className="text-base text-foreground-light dark:text-foreground-dark">
                    {health.solid_queue_failed}
                </Text>
            }
        />
    </View>
);

export default function AdminHubScreen({ navigation }: Props) {
    const nav = useNavigation();
    const { data, loading, error, refresh } = useAdminHub();

    const renderTool = (tool: AdminTool) => {
        const routeName = adminToolScreens[tool.id];
        const opensOnMobile = routeName !== undefined && !tool.external;
        return (
            <ListRow
                key={tool.id}
                testID={`admin-tool-${tool.id}`}
                label={tool.label}
                description={opensOnMobile ? tool.description : NOT_ON_MOBILE_YET}
                onPress={opensOnMobile ? () => navigation.navigate(routeName) : undefined}
            />
        );
    };

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark">
            <BrandHeader
                title="Admin"
                testID="admin-brand-header"
                onMenuPress={() => nav.dispatch(DrawerActions.openDrawer())}
            />
            <ScrollView
                contentContainerStyle={{ paddingBottom: 24 }}
                refreshControl={
                    <RefreshControl
                        refreshing={loading && data !== null}
                        onRefresh={() => {
                            void refresh();
                        }}
                        accessibilityLabel="Pull to refresh the admin hub"
                    />
                }
            >
                {error ? (
                    <EmptyState title={error.message} testID="admin-hub-error" />
                ) : data === null ? (
                    <ActivityIndicator testID="admin-hub-loading" className="py-12" />
                ) : (
                    <>
                        {groupTools(data.tools).map(([group, tools]) => (
                            <View key={group}>
                                <GroupHeading title={group} />
                                {tools.map(renderTool)}
                            </View>
                        ))}
                        {data.database_health ? <DatabaseHealthList health={data.database_health} /> : null}
                    </>
                )}
            </ScrollView>
        </View>
    );
}
