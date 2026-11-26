// @lat: [[well-known-controller-notes#Mobile: linking.ts#A bill share link opens the shared bill]]
import React, { useEffect, useState } from "react";
import { View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { SkeletonCard } from "../components/SkeletonCard";
import { EmptyState } from "../components/ui/EmptyState";
import type { BillsStackParamList } from "../navigation/types";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

interface IProps {
    route: { params?: { shareUuid?: string } };
}

const SHARE_UUID = /^[0-9a-f-]+$/i;

const BillShareScreen: React.FC<IProps> = ({ route }) => {
    const navigation = useNavigation<NativeStackNavigationProp<BillsStackParamList, "BillShare">>();
    const shareUuid = route.params?.shareUuid ?? "";
    const isShareUuid = SHARE_UUID.test(shareUuid);
    const [failed, setFailed] = useState(!isShareUuid);

    useEffect(() => {
        setFailed(!isShareUuid);
        if (!isShareUuid) return undefined;

        let stillShowing = true;
        apiClient
            .get<{ bill_id: number }>(Routes.billShare(shareUuid))
            .then((share) => {
                if (stillShowing) navigation.replace("BillDetail", { id: share.bill_id });
            })
            .catch(() => {
                if (stillShowing) setFailed(true);
            });
        return () => {
            stillShowing = false;
        };
    }, [isShareUuid, navigation, shareUuid]);

    return (
        <View className="flex-1 bg-dominant-light p-6 dark:bg-dominant-dark">
            {failed ? (
                <EmptyState
                    title="Bill not found."
                    ctaLabel={PARITY_COPY.billOfTheMonth.browseBills}
                    onCtaPress={() => navigation.replace("BillsList")}
                    testID="bill-share-error"
                />
            ) : (
                <View testID="bill-share-loading">
                    <SkeletonCard heightClass="h-32" />
                </View>
            )}
        </View>
    );
};

export default BillShareScreen;
