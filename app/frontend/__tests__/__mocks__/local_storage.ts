/**
 * An in-memory stand-in for window.localStorage.
 *
 // @lat: [[frontend-test-infrastructure-notes#Why the local_storage mock needs an in-memory stand-in]]
 */
export const installLocalStorage = (): Storage => {
    const store = new Map<string, string>();

    const stub: Storage = {
        get length() {
            return store.size;
        },
        clear: () => store.clear(),
        getItem: (key: string) => (store.has(key) ? (store.get(key) as string) : null),
        key: (index: number) => Array.from(store.keys())[index] ?? null,
        removeItem: (key: string) => {
            store.delete(key);
        },
        setItem: (key: string, value: string) => {
            store.set(key, String(value));
        },
    };

    Object.defineProperty(window, "localStorage", { configurable: true, writable: true, value: stub });

    return stub;
};

/** A storage that refuses every call, as a browser does when it is switched off. */
export const installBrokenLocalStorage = (): void => {
    const refuse = () => {
        throw new Error("storage is disabled");
    };

    Object.defineProperty(window, "localStorage", {
        configurable: true,
        writable: true,
        value: { getItem: refuse, setItem: refuse, removeItem: refuse, clear: refuse, key: refuse, length: 0 },
    });
};

/** Put the window back the way this environment normally has it: no storage. */
export const removeLocalStorage = (): void => {
    Object.defineProperty(window, "localStorage", { configurable: true, writable: true, value: undefined });
};
