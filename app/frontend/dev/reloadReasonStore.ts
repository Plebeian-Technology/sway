// @lat: [[dev-reload-reason-diagnostic#Why sessionStorage, and why per-tab]]

export interface IReloadReason {
    event: string;
    at: number;
    path: string;
}

const STORAGE_KEY = "sway.dev.reload_reasons";

// @lat: [[dev-reload-reason-diagnostic#Development only]]
const MAX_KEPT_RELOAD_REASONS = 10;

const isReason = (value: unknown): value is IReloadReason => {
    const reason = value as IReloadReason | null;
    return typeof reason?.event === "string" && typeof reason?.at === "number" && typeof reason?.path === "string";
};

// @lat: [[dev-reload-reason-diagnostic#Why sessionStorage, and why per-tab]]
export const readReloadReasons = (storage: Storage): IReloadReason[] => {
    try {
        const raw = storage.getItem(STORAGE_KEY);
        if (!raw) return [];
        const parsed: unknown = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed.filter(isReason) : [];
    } catch {
        return [];
    }
};

export const appendReloadReason = (storage: Storage, reason: IReloadReason): void => {
    try {
        const kept = [...readReloadReasons(storage), reason].slice(-MAX_KEPT_RELOAD_REASONS);
        storage.setItem(STORAGE_KEY, JSON.stringify(kept));
    } catch {
        // @lat: [[dev-reload-reason-diagnostic#Why sessionStorage, and why per-tab]]
    }
};
