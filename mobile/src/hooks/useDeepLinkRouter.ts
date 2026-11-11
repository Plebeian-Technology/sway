// @lat: [[mobile-deep-link-router-hook#Which screen wins]]
import { useEffect } from "react";
import * as Notifications from "expo-notifications";
import type { NavigationContainerRef } from "@react-navigation/native";

type NavData = {
    bill_id?: string | number;
    legislator_id?: string | number;
    deep_link?: string;
    kind?: string;
};

export function useDeepLinkRouter(navRef: React.RefObject<NavigationContainerRef<any> | null>): void {
    useEffect(() => {
        const sub = Notifications.addNotificationResponseReceivedListener((res) => {
            const data = (res.notification.request.content.data ?? {}) as NavData;
            const nav = navRef.current;
            if (!nav) return;

            // @lat: [[mobile-deep-link-router-hook#Why the navigation call is retyped through unknown]]
            const navAny = nav as unknown as { navigate: (route: string, params?: unknown) => void };
            if (data.bill_id != null) {
                navAny.navigate("Bills", {
                    screen: "BillDetail",
                    params: { id: Number(data.bill_id) },
                });
            } else if (data.legislator_id != null) {
                navAny.navigate("Legislators", {
                    screen: "LegislatorDetail",
                    params: { id: Number(data.legislator_id) },
                });
            }
        });
        return () => sub.remove();
    }, [navRef]);
}
