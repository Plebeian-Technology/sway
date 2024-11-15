import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";

export const TempBillStorage = {
    set: (values: Record<string, any>) => {
        localStorage.setItem(SWAY_STORAGE.Local.BillOfTheWeek.Temp, JSON.stringify(values));
        notify({ level: "success", title: "Temporary Bill Stored", duration: 1000 });
    },
    remove: () => {
        localStorage.removeItem(SWAY_STORAGE.Local.BillOfTheWeek.Temp);
        notify({ level: "warning", title: "Temporary Bill Removed", duration: 1000 });
    },
    get: () => {
        const stored = localStorage.getItem(SWAY_STORAGE.Local.BillOfTheWeek.Temp);
        if (stored) {
            window.setTimeout(() => {
                notify({ level: "info", title: "Loaded Bill From Temp Storage", duration: 1000 });
            }, 100);
            return JSON.parse(stored);
        } else {
            return null;
        }
    },
};
