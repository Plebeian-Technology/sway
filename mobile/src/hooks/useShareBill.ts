// @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]
import { useCallback, useRef } from "react";
import { Share } from "react-native";
import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { tokenStore } from "../auth/tokenStore";
import { API_BASE_URL } from "../constants/api";

export interface ShareBillTarget {
    id?: number;
    title?: string;
}

export interface UseShareBillResult {
    shareBill: (bill: ShareBillTarget) => Promise<void>;
}

export function useShareBill(): UseShareBillResult {
    const inFlightRef = useRef(false);

    const shareBill = useCallback(async (bill: ShareBillTarget): Promise<void> => {
        if (bill.id == null || inFlightRef.current) return;
        inFlightRef.current = true;

        try {
            const defaultUrl = `${API_BASE_URL}/bills/${bill.id}`;
            let shareUrl = defaultUrl;

            try {
                const token = await tokenStore.get();
                if (token) {
                    const res = await apiClient.post<{ share_path?: string }>(Routes.userBillShares(), {
                        bill_id: bill.id,
                    });
                    if (res?.share_path) {
                        shareUrl = `${API_BASE_URL}${res.share_path}`;
                    }
                }
            } catch {
                shareUrl = defaultUrl;
            }

            try {
                await Share.share({
                    message: shareUrl,
                    url: shareUrl,
                });
            } catch {
                return;
            }
        } finally {
            inFlightRef.current = false;
        }
    }, []);

    return { shareBill };
}
