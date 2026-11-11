import { router } from "@inertiajs/react";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import { useCallback, useState } from "react";

// @lat: [[organization-position-removal#The button only reaches the server for a position that exists]]
export const useRemoveOrgPosition = (
    tabKey: string,
): {
    removing: boolean;
    removePosition: (positionId: number | undefined, onRemoved: () => void) => void;
} => {
    const [removing, setRemoving] = useState<boolean>(false);

    const removePosition = useCallback(
        (positionId: number | undefined, onRemoved: () => void) => {
            if (!positionId) {
                onRemoved();
                return;
            }
            setRemoving(true);
            router.delete(`/organization_bill_positions/${positionId}?bill_creator_tab=${encodeURIComponent(tabKey)}`, {
                preserveScroll: true,
                onSuccess: (page) => {
                    if (pageExpired(page)) return;
                    onRemoved();
                },
                onFinish: () => setRemoving(false),
            });
        },
        [tabKey],
    );

    return { removing, removePosition };
};

export default useRemoveOrgPosition;
