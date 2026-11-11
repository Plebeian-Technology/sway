// @lat: [[mobile-orgs-list-screen#OrgsListScreen]]
import React, { useCallback, useEffect, useState } from "react";
import { FlatList, RefreshControl, ScrollView, View } from "react-native";
import { DrawerActions, useNavigation } from "@react-navigation/native";

import BrandHeader from "../components/BrandHeader";
import { OrgCard, type OrgCardOrganization } from "../components/OrgCard";
import { OfflineBanner } from "../components/OfflineBanner";
import { EmptyState } from "../components/ui/EmptyState";
import { FadeInItem } from "../components/ui/FadeInItem";
import { SwayLocalePickerSheet } from "../components/SwayLocalePickerSheet";
import { useBootstrap } from "../hooks/useBootstrap";
import { useOrganizations } from "../hooks/useOrganizations";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { toFormattedLocaleName } from "../utils/locale";

interface NavLike {
    navigate: (screen: string, params?: Record<string, unknown>) => void;
}

interface Props {
    navigation: NavLike;
}

export default function OrgsListScreen({ navigation }: Props) {
    const nav = useNavigation();
    const { bootstrap } = useBootstrap();

    const initialLocaleId = bootstrap?.locale?.id ?? 0;
    const [activeLocaleId, setActiveLocaleId] = useState(initialLocaleId);

    useEffect(() => {
        setActiveLocaleId(initialLocaleId);
    }, [initialLocaleId]);

    const { data, loading, refresh, isOnline } = useOrganizations({ swayLocaleId: activeLocaleId });

    const orgs = data?.organizations ?? [];

    const isSignedIn = data?.user_follows !== undefined;

    const swayLocales = bootstrap?.sway_locales;
    const activeLocale = swayLocales?.find((l) => l.id === activeLocaleId) ?? bootstrap?.locale ?? undefined;

    const formattedSwayLocaleName = activeLocale?.name
        ? toFormattedLocaleName(activeLocale.name, false)
        : "your locale";

    const keyExtractor = useCallback(
        (item: OrgCardOrganization) => `${item.id}-${data?.user_follows?.[item.id] ?? "none"}`,
        [data?.user_follows],
    );

    const renderItem = useCallback(
        ({ item, index }: { item: OrgCardOrganization; index: number }) => (
            <FadeInItem index={index}>
                <View className="px-4">
                    <OrgCard
                        org={item}
                        onPress={() => navigation.navigate("OrgDetail", { id: item.id })}
                        isSignedIn={isSignedIn}
                        isMember={data?.is_member_of_org_ids?.includes(item.id) ?? false}
                        initialFollowId={data?.user_follows?.[item.id] ?? null}
                        initialPrefs={data?.user_follow_prefs?.[item.id]}
                        defaultPrefs={data?.current_user_org_defaults}
                        onRequestSignIn={() => {
                            navigation.navigate("Auth" as never);
                        }}
                    />
                </View>
            </FadeInItem>
        ),
        [navigation, isSignedIn, data],
    );

    const localePicker = (
        <View className="py-3">
            <SwayLocalePickerSheet
                locales={swayLocales ?? []}
                currentLocale={activeLocale ?? null}
                onSelect={(id) => setActiveLocaleId(id)}
                testID="locale-picker-trigger"
            />
        </View>
    );

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark">
            {!isOnline ? <OfflineBanner /> : null}

            <BrandHeader
                title={PARITY_COPY.orgs.title}
                testID="orgs-brand-header"
                onMenuPress={() => nav.dispatch(DrawerActions.openDrawer())}
            />

            {orgs.length === 0 ? (
                <ScrollView contentContainerStyle={{ paddingBottom: 24 }}>
                    {localePicker}
                    <EmptyState title={PARITY_COPY.orgs.noneFound(formattedSwayLocaleName)} testID="orgs-empty-state" />
                </ScrollView>
            ) : (
                <FlatList<OrgCardOrganization>
                    testID="orgs-list"
                    data={orgs}
                    keyExtractor={keyExtractor}
                    renderItem={renderItem}
                    // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
                    ListHeaderComponent={localePicker}
                    contentContainerStyle={{ paddingBottom: 24 }}
                    refreshControl={
                        <RefreshControl
                            refreshing={loading}
                            onRefresh={() => {
                                void refresh();
                            }}
                            accessibilityLabel="Pull to refresh organizations list"
                        />
                    }
                />
            )}
        </View>
    );
}
