/* Jest setup for jest-expo. Mocks the native-only modules so component tests
 * can render the full App tree without needing the OS bridges. Wave 0 mocks per
 * VALIDATION.md "Wave 0 Requirements". Real integration tests land in plans 05+. */

// IMPORTANT: jest.mock(...) factories may NOT reference identifiers transformed
// by babel-preset-expo (nativewind injects _ReactNativeCSSInterop into many
// modules). Keep factories self-contained; pull React/View via require() inside.

jest.mock("expo-secure-store", () => ({
    getItemAsync: jest.fn(async () => null),
    setItemAsync: jest.fn(async () => {}),
    deleteItemAsync: jest.fn(async () => {}),
}));

jest.mock("expo-notifications", () => ({
    getPermissionsAsync: jest.fn(async () => ({ status: "undetermined", canAskAgain: true })),
    requestPermissionsAsync: jest.fn(async () => ({ status: "granted" })),
    // H2 (Phase 32 Plan 11): Sway uses NATIVE device tokens (FCM/APNs),
    // not Expo push tokens. getExpoPushTokenAsync remains stubbed only so
    // usePushToken tests can assert "not called"; production code uses
    // getDevicePushTokenAsync instead.
    getDevicePushTokenAsync: jest.fn(async () => ({ data: "native-token-mock" })),
    getExpoPushTokenAsync: jest.fn(async () => ({ data: "ExponentPushToken[xxx]" })),
    addPushTokenListener: jest.fn(() => ({ remove: jest.fn() })),
    addNotificationResponseReceivedListener: jest.fn(() => ({ remove: jest.fn() })),
}));

// react-native-passkey is added by plan 06 (auth wave). The mock is registered
// here with `virtual: true` so test files that *will* import it after plan 06
// don't need a separate setup, and current Wave 0 tests don't fail on the
// uninstalled module.
jest.mock(
    "react-native-passkey",
    () => ({
        Passkey: {
            isSupported: jest.fn(() => true),
            create: jest.fn(async () => ({
                id: "x",
                rawId: "x",
                response: {},
                type: "public-key",
            })),
            get: jest.fn(async () => ({
                id: "x",
                rawId: "x",
                response: {},
                type: "public-key",
            })),
        },
    }),
    { virtual: true },
);

// expo-font is mocked so test renders never block on font load.
jest.mock("expo-font", () => ({
    useFonts: () => [true],
    isLoaded: jest.fn(() => true),
}));

// Sentry must NOT initialize during tests (no DSN, no network).
jest.mock("@sentry/react-native", () => ({
    init: jest.fn(),
    captureException: jest.fn(),
    captureMessage: jest.fn(),
}));

// @lat: [[mobile-expo-config#The Expo config file and the mobile type check#What the mobile test environment has to stand in for]]
// oxlint-disable-next-line @typescript-eslint/no-require-imports
jest.mock("react-native-reanimated", () => require("react-native-reanimated/mock"));

// oxlint-disable-next-line @typescript-eslint/no-require-imports
jest.mock("react-native-worklets", () => require("react-native-worklets/lib/module/mock"));

require("react-native-gesture-handler/jestSetup");

jest.mock("react-native/src/private/devsupport/devmenu/DevMenu", () => ({}));
jest.mock("react-native/src/private/devsupport/devmenu/specs/NativeDevMenu", () => ({
    default: {
        show: () => {},
        reload: () => {},
        debugRemotely: () => {},
        setProfilingEnabled: () => {},
        setHotLoadingEnabled: () => {},
        addMenuItem: () => {},
    },
}));

jest.mock("@react-native-community/netinfo", () => ({
    addEventListener: jest.fn(() => () => {}),
    fetch: jest.fn(async () => ({ isConnected: true, isInternetReachable: true, type: "wifi" })),
    useNetInfo: () => ({ isConnected: true, isInternetReachable: true, type: "wifi" }),
    configure: jest.fn(),
    refresh: jest.fn(async () => ({ isConnected: true, isInternetReachable: true })),
}));

jest.mock("@rails/actioncable", () => ({
    createConsumer: jest.fn(() => ({
        subscriptions: {
            create: jest.fn(() => ({ unsubscribe: jest.fn(), perform: jest.fn() })),
        },
        connection: { isOpen: () => false, open: jest.fn(), close: jest.fn() },
        disconnect: jest.fn(),
    })),
    Consumer: jest.fn(),
}));

jest.mock("@react-navigation/native", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const actual = jest.requireActual("@react-navigation/native");
    const ReactMod = jest.requireActual("react");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        ...actual,
        useNavigation: () => ({
            navigate: jest.fn(),
            goBack: jest.fn(),
            push: jest.fn(),
            pop: jest.fn(),
            replace: jest.fn(),
            reset: jest.fn(),
            setOptions: jest.fn(),
            addListener: jest.fn(() => jest.fn()),
            removeListener: jest.fn(),
            canGoBack: () => false,
            isFocused: () => true,
            getState: () => ({ routes: [], index: 0 }),
            getParent: () => undefined,
        }),
        useRoute: () => ({ key: "test", name: "Test", params: {} }),
        // @lat: [[mobile-test-infrastructure-notes#jest.setup.ts: why the useFocusEffect mock has no dependency list]]
        useFocusEffect: (cb: () => void | (() => void)) => {
            ReactMod.useEffect(() => cb());
        },
        useIsFocused: () => true,
    };
});

jest.mock("expo-sqlite", () => {
    const stubDb = {
        execAsync: jest.fn(async () => {}),
        runAsync: jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 })),
        getAllAsync: jest.fn(async () => []),
        getFirstAsync: jest.fn(async () => null),
        closeAsync: jest.fn(async () => {}),
        withTransactionAsync: jest.fn(async (cb: () => Promise<void>) => cb()),
    };
    return {
        openDatabaseAsync: jest.fn(async () => stubDb),
        openDatabaseSync: jest.fn(() => stubDb),
        deleteDatabaseAsync: jest.fn(async () => {}),
        SQLiteProvider: ({ children }: { children: React.ReactNode }) => children,
    };
});

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    notificationAsync: jest.fn(async () => {}),
    selectionAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "light", Medium: "medium", Heavy: "heavy", Soft: "soft", Rigid: "rigid" },
    NotificationFeedbackType: { Success: "success", Warning: "warning", Error: "error" },
}));

// Lucide icons would otherwise drag in react-native-svg's full transform; stub
// every icon as a simple View via a Proxy so the allowlist doesn't need
// maintenance when new icons (X, ArrowUp, Building2, etc.) are imported by
// new screens. Each access returns a named React component that renders an
// empty View — sufficient for testID-based queries.
jest.mock("lucide-react-native", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    const Stub = (name: string) => {
        const C = function LucideStub() {
            return ReactMod.createElement(RNMod.View, { testID: `lucide-${name.toLowerCase()}` });
        };
        C.displayName = `LucideStub(${name})`;
        return C;
    };
    return new Proxy(
        {},
        {
            get: (_target, prop: string) => {
                if (typeof prop === "symbol" || prop === "default" || prop === "__esModule") return undefined;
                return Stub(prop);
            },
        },
    );
});

// SafeAreaProvider waits for an inset measurement before rendering children in
// the real native layout pass; under jest there is no native bridge to supply
// that measurement so children would never mount. Provide a minimal mock that
// (a) renders children immediately and (b) carries the named exports nativewind's
// css-interop expects (SafeAreaView, useSafeAreaInsets, etc.) so the wrap-jsx
// runtime can look them up by displayName without crashing.
jest.mock("react-native-safe-area-context", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    const Pass = (name: string) => {
        const C = ({ children }: { children?: React.ReactNode }) => ReactMod.createElement(RNMod.View, null, children);
        C.displayName = name;
        return C;
    };
    const SafeAreaView = Pass("SafeAreaView");
    const SafeAreaProvider = Pass("SafeAreaProvider");
    return {
        SafeAreaProvider,
        SafeAreaView,
        SafeAreaInsetsContext: ReactMod.createContext({
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
        }),
        SafeAreaFrameContext: ReactMod.createContext({
            x: 0,
            y: 0,
            width: 0,
            height: 0,
        }),
        useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
        useSafeAreaFrame: () => ({ x: 0, y: 0, width: 0, height: 0 }),
        initialWindowMetrics: {
            insets: { top: 0, left: 0, right: 0, bottom: 0 },
            frame: { x: 0, y: 0, width: 0, height: 0 },
        },
    };
});

// jest-native matchers (deprecated in favour of @testing-library/react-native v12+
// built-ins, but kept here so existing toBeTruthy assertions remain compatible).
// Loaded via require() AFTER all jest.mock() calls so its imports are not
// hoisted alongside mock factories.
require("@testing-library/jest-native/extend-expect");
