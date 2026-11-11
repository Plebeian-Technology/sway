// @lat: [[temp-bill-storage-peek-parsing#Why TempBillStorage is shaped the way it is]]
import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";

export class TempBillStorage {
    readonly key: string;

    constructor(key?: string) {
        this.key = key || SWAY_STORAGE.Local.BillCreator.Bill;
    }

    static remove() {
        new TempBillStorage(SWAY_STORAGE.Local.BillCreator.Bill).remove();
        new TempBillStorage(SWAY_STORAGE.Local.BillCreator.Organizations).remove();
        new TempBillStorage(SWAY_STORAGE.Local.BillCreator.LegislatorVotes).remove();
    }

    static clear() {
        TempBillStorage.remove();
    }

    name() {
        return {
            [SWAY_STORAGE.Local.BillCreator.Bill]: "Bill",
            [SWAY_STORAGE.Local.BillCreator.Organizations]: "Supporting/Opposing Arguments",
            [SWAY_STORAGE.Local.BillCreator.LegislatorVotes]: "Legislator Votes",
        }[this.key];
    }

    set<T extends object>(values: T) {
        localStorage.setItem(this.key, JSON.stringify(values));
        notify({ level: "success", title: "Temporary Data Stored", duration: 1000 });
    }

    remove() {
        localStorage.removeItem(this.key);
        notify({ level: "warning", title: "Temporary Data Removed", duration: 1000 });
    }

    clear() {
        this.remove();
    }

    // @lat: [[temp-bill-storage-peek-parsing#A bad parse returns null on purpose]]
    peek(): unknown {
        const stored = localStorage.getItem(this.key);
        if (stored === null) return null;

        try {
            return JSON.parse(stored) as unknown;
        } catch {
            return null;
        }
    }
}
