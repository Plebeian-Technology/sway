import { router, usePage } from "@inertiajs/react";
import { useCallback, useMemo, useState } from "react";
import { notify } from "app/frontend/sway_utils";
import { ROUTES } from "app/frontend/sway_constants";
import type { sway } from "sway";

export const useReassignmentNotifications = () => {
    const { props } = usePage<sway.IPageProps>();
    const rawNotifications = useMemo(
        () => props.reassignment_notifications ?? props.representative_reassignments ?? [],
        [props.reassignment_notifications, props.representative_reassignments],
    );
    const [dismissedIds, setDismissedIds] = useState<number[]>([]);

    const activeNotifications = useMemo(
        () => rawNotifications.filter((n) => !dismissedIds.includes(n.id) && !n.dismissed_at),
        [rawNotifications, dismissedIds],
    );

    const dismiss = useCallback((id: number) => {
        setDismissedIds((prev) => [...prev, id]);

        const route = ROUTES.reassignmentDismiss
            ? ROUTES.reassignmentDismiss(id)
            : ROUTES.dismissReassignmentNotification(id);

        router.patch(
            route,
            {},
            {
                preserveScroll: true,
                preserveState: true,
                onError: () => {
                    setDismissedIds((prev) => prev.filter((item) => item !== id));
                    notify({ level: "error", title: "Could not dismiss notification. Please try again." });
                },
            },
        );
    }, []);

    return { notifications: activeNotifications, dismiss };
};

export default useReassignmentNotifications;
