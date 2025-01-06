import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";

export class TempBillStorage {
    readonly key: string;
    constructor(key: string) {
        this.key = key || SWAY_STORAGE.Local.BillOfTheWeek.Bill;
    }
    static remove() {
        new TempBillStorage(SWAY_STORAGE.Local.BillOfTheWeek.Bill).remove();
        new TempBillStorage(SWAY_STORAGE.Local.BillOfTheWeek.Organizations).remove();
        new TempBillStorage(SWAY_STORAGE.Local.BillOfTheWeek.LegislatorVotes).remove();
    }

    name() {
        return {
            [SWAY_STORAGE.Local.BillOfTheWeek.Bill]: "Bill",
            [SWAY_STORAGE.Local.BillOfTheWeek.Organizations]: "Supporting/Opposing Arguments",
            [SWAY_STORAGE.Local.BillOfTheWeek.LegislatorVotes]: "Legislator Votes",
        }[this.key];
    }

    set(values: Record<string, any>) {
        localStorage.setItem(this.key, JSON.stringify(values));
        notify({ level: "success", title: "Temporary Data Stored", duration: 1000 });
    }

    remove() {
        localStorage.removeItem(this.key);
        notify({ level: "warning", title: "Temporary Data Removed", duration: 1000 });
    }

    get() {
        const stored = localStorage.getItem(this.key);
        if (stored) {
            window.setTimeout(() => {
                notify({ level: "info", title: "Loaded Data from Temp Storage", duration: 1000 });
            }, 100);
            return JSON.parse(stored);
        } else {
            return null;
        }
    }
}
