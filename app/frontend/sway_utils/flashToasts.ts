import { router } from "@inertiajs/react";

import { notify } from "app/frontend/sway_utils";

interface Flash {
    id?: string;
    notice?: string;
    alert?: string;
}

const dedupeKey = (message: string | undefined, id: string | undefined): string | undefined =>
    message === undefined ? undefined : (id ?? message);

// @lat: [[toasts#Flash toast dedupe]]
export const registerFlashToasts = (): void => {
    let lastNoticeKey: string | undefined;
    let lastAlertKey: string | undefined;

    router.on("success", (event) => {
        const flash = event.detail.page.props.flash as Flash | undefined;
        const notice = flash?.notice;
        const alert = flash?.alert;
        const noticeKey = dedupeKey(notice, flash?.id);
        const alertKey = dedupeKey(alert, flash?.id);

        if (notice && noticeKey !== lastNoticeKey) {
            notify({ level: "success", title: notice, duration: 5000 });
        }
        if (alert && alertKey !== lastAlertKey) {
            notify({ level: "error", title: alert, duration: 5000 });
        }
        lastNoticeKey = noticeKey;
        lastAlertKey = alertKey;
    });
};
