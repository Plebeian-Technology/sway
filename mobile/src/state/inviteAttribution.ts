// @lat: [[well-known-controller-notes#Mobile: linking.ts#Invite links store a key and open no screen]]
let _key: string | null = null;

export const inviteAttribution = {
    get(): string | null {
        return _key;
    },
    set(key: string): void {
        _key = key;
    },
    clear(): void {
        _key = null;
    },
};
