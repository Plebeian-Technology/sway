// @lat: [[mobile-locale-override-design#Why a module-level value and not React state]]
let _override: number | null = null;

export const localeOverride = {
    get(): number | null {
        return _override;
    },
    set(id: number | null): void {
        _override = id;
    },
    clear(): void {
        _override = null;
    },
};
