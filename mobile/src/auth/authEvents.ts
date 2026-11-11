// @lat: [[mobile-api-client-contract#Why authEvents imports nothing]]
export type AuthEvent = "signed_in" | "signed_out" | "unauthenticated";

type Listener = (e: AuthEvent) => void;

const listeners = new Set<Listener>();

export const authEvents = {
    on(cb: Listener): () => void {
        listeners.add(cb);
        return () => {
            listeners.delete(cb);
        };
    },
    emit(e: AuthEvent): void {
        for (const cb of Array.from(listeners)) {
            try {
                cb(e);
            } catch {}
        }
    },
    _reset(): void {
        listeners.clear();
    },
};
