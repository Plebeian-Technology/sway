// @lat: [[mobile-api-client-contract#Why authEvents imports nothing]]
export type AuthEvent = "signed_in" | "signed_out" | "unauthenticated";
export type UnauthenticatedReason = "session_expired";

type Listener = (e: AuthEvent) => void;

const listeners = new Set<Listener>();

let unauthenticatedReason: UnauthenticatedReason | null = null;

export const authEvents = {
    on(cb: Listener): () => void {
        listeners.add(cb);
        return () => {
            listeners.delete(cb);
        };
    },
    // Reason for the latest unauthenticated event; null once anyone signs in or out.
    unauthenticatedReason(): UnauthenticatedReason | null {
        return unauthenticatedReason;
    },
    emit(e: AuthEvent, reason?: UnauthenticatedReason): void {
        unauthenticatedReason = e === "unauthenticated" ? (reason ?? null) : null;
        for (const cb of Array.from(listeners)) {
            try {
                cb(e);
            } catch {}
        }
    },
    _reset(): void {
        listeners.clear();
        unauthenticatedReason = null;
    },
};
