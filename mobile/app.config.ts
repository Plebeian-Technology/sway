import { ExpoConfig, ConfigContext } from "expo/config";
import * as fs from "fs";
import * as path from "path";

import { ConfigPlugin, withGradleProperties, AndroidConfig } from "expo/config-plugins";

// @lat: [[mobile-app-config-ts-import-extension#Why the list is not simply copied into the config]]
import { DEEP_LINK_PATTERNS, androidPathData } from "./src/navigation/deepLinkPatterns.ts";

// Plugin to set kotlin.jvm.target.validation.mode=warning in android/gradle.properties
// Prevents Gradle failure when libraries (like react-native-passkey) declare Java 1.8 compatibility
// while the root Kotlin compiler runs against JVM target 17/21.
const withKotlinTargetValidationWarning: ConfigPlugin = (config) => {
    return withGradleProperties(config, (modConfig) => {
        modConfig.modResults = AndroidConfig.BuildProperties.updateAndroidBuildProperty(
            modConfig.modResults,
            "kotlin.jvm.target.validation.mode",
            "warning",
        );
        return modConfig;
    });
};

// Single source of truth for dynamic + static Expo config (per Task 0 single-config consolidation).
// app.json is intentionally a stub holding only name + slug; everything else is set here so the
// build matrix (bundle id, team id, AASA, intent filters, plugins, extras) is unified.

// Resolve a Firebase services file only when it actually exists. Without this guard, Expo's
// withGoogleServicesFile mod tries to copyFileSync a phantom path and prebuild --clean fails.
// Direct APNs (via apnotic) is the default push transport, so these files are optional in dev.
const resolveGoogleServicesFile = (envVar: string, defaultPath: string): string | undefined => {
    const candidate = process.env[envVar] ?? defaultPath;
    const absolute = path.isAbsolute(candidate) ? candidate : path.join(__dirname, candidate);
    return fs.existsSync(absolute) ? candidate : undefined;
};

// Sentry's Expo plugin injects a native build phase that runs `sentry-cli` to upload
// source maps. That step requires SENTRY_AUTH_TOKEN and fails the build when absent.
const enableSentry = Boolean(process.env.SENTRY_AUTH_TOKEN);

// @lat: [[mobile-sentry-init-design#Why the DSN is trimmed at config time]]
const resolveSentryDsn = (): string | undefined => process.env.SENTRY_DSN_MOBILE?.trim() || undefined;

// @lat: [[android-app-links]]
const androidLinkData = (host: string) =>
    DEEP_LINK_PATTERNS.map((pattern) => ({
        scheme: "https",
        host,
        ...androidPathData(pattern),
    }));

// @lat: [[mobile-expo-config#Deployment identifiers come from the environment]]
const appleTeamId = process.env.APPLE_TEAM_ID || undefined;
const expoOwner = process.env.EXPO_OWNER || undefined;
const easProjectId = process.env.EAS_PROJECT_ID || undefined;

// @lat: [[mobile-expo-config#Deployment identifiers come from the environment#Why a missing bundle id stops the config]]
const requireBundleId = (): string => {
    const bundleId = process.env.APPLE_BUNDLE_ID;
    if (bundleId) return bundleId;

    throw new Error(
        "APPLE_BUNDLE_ID is unset. Export it, or run through mobile/scripts/with-vault-env.sh, which reads it from the secret-store item SWAY_BUNDLE_ID.",
    );
};

// @lat: [[mobile-expo-config#Deployment identifiers come from the environment#The dev tunnel host is claimed only when set]]
const devTunnelDomains = (host: string | undefined): string[] =>
    host ? [`webcredentials:${host}?mode=developer`, `applinks:${host}?mode=developer`] : [];

export default ({ config }: ConfigContext): ExpoConfig => {
    const bundleId = requireBundleId();
    const devTunnelHost = process.env.EXPO_PUBLIC_DEV_TUNNEL_HOST || undefined;

    return withKotlinTargetValidationWarning({
        ...(config as ExpoConfig),
        ...(expoOwner ? { owner: expoOwner } : {}),
        name: config.name ?? "Sway",
        slug: config.slug ?? "sway-mobile",
        version: "1.0.0",
        orientation: "portrait",
        userInterfaceStyle: "automatic",
        scheme: "sway",
        icon: "./assets/icon.png",
        ios: {
            // @lat: [[mobile-expo-config#Why each platform block extends the static config]]
            ...(config.ios ?? {}),
            bundleIdentifier: bundleId,
            ...(appleTeamId ? { appleTeamId } : {}),
            associatedDomains: [
                "webcredentials:app.sway.vote",
                "applinks:sway.vote",
                ...devTunnelDomains(devTunnelHost),
            ],
            supportsTablet: false,
            // @lat: [[local-store-uploads#Why export compliance is declared in the config]]
            infoPlist: {
                ITSAppUsesNonExemptEncryption: false,
            },
            // Phase 32 Plan 11 (H2 — optional): GoogleService-Info.plist registers
            // iOS through FCM's APNs-bridge if present. The default backend strategy
            // is direct APNs via apnotic (see app/services/apns_client.rb), so this
            // file is only required if iOS push is routed through Firebase. Loaded
            // from env so CI/EAS can inject the path without committing the file.
            googleServicesFile: resolveGoogleServicesFile("GOOGLE_SERVICE_INFO_PLIST", "./GoogleService-Info.plist"),
        },
        android: {
            // @lat: [[mobile-expo-config#Why each platform block extends the static config]]
            ...(config.android ?? {}),
            package: bundleId,
            adaptiveIcon: {
                foregroundImage: "./assets/adaptive-icon.png",
            },
            // Phase 32 Plan 11 (H2): google-services.json so Expo wires the native
            // FCM client; getDevicePushTokenAsync() then returns a NATIVE FCM
            // registration token (not an ExponentPushToken). Loaded from env so
            // CI can inject the file path without committing it to the repo.
            googleServicesFile: resolveGoogleServicesFile("GOOGLE_SERVICES_JSON", "./google-services.json"),
            intentFilters: [
                {
                    action: "VIEW",
                    autoVerify: true,
                    data: androidLinkData("sway.vote"),
                    category: ["BROWSABLE", "DEFAULT"],
                },
                // Dev tunnel parity with iOS associatedDomains. autoVerify still requires
                // ANDROID_CERT_SHA256_FINGERPRINTS to be set so /.well-known/assetlinks.json
                // returns a populated array on the dev host — until then, links open via
                // disambiguation chooser (still functional, just not auto-opened).
                ...(devTunnelHost
                    ? [
                          {
                              action: "VIEW",
                              autoVerify: true,
                              data: androidLinkData(devTunnelHost),
                              category: ["BROWSABLE", "DEFAULT"],
                          },
                      ]
                    : []),
            ],
        },
        plugins: [
            "expo-font",
            ["expo-notifications", { icon: "./assets/notification-icon.png" }],
            "expo-secure-store",
            "expo-sqlite",
            "expo-web-browser",
            // App-store launch screen. backgroundColor mirrors the flat Sway
            // --background token: #f7f9fc (light) / #212529 (dark). Keeps the
            // cold-start splash aligned with the app shell so there's no cream
            // flash before the React tree renders.
            [
                "expo-splash-screen",
                {
                    image: "./assets/splash-icon.png",
                    imageWidth: 240,
                    resizeMode: "contain",
                    backgroundColor: "#f7f9fc",
                    dark: {
                        image: "./assets/splash-icon.png",
                        backgroundColor: "#212529",
                    },
                },
            ],
            ...(enableSentry ? ["@sentry/react-native/expo" as const] : []),
            // iOS 15+ matches react-native-passkey's floor and silences the
            // Sentry deployment-target warning (Sentry SDK requires >= 12).
            // Android Credential Manager / native passkey requires API 28+
            // (react-native-passkey throws PasskeyNotSupported below this).
            [
                "expo-build-properties",
                {
                    ios: { deploymentTarget: "15.1" },
                    android: { minSdkVersion: 28 },
                },
            ],
        ],
        extra: {
            ...config.extra,
            ...(easProjectId ? { eas: { projectId: easProjectId } } : {}),
            apiBaseUrl: process.env.EXPO_PUBLIC_API_URL || "https://app.sway.vote",
            webauthnRpId: "app.sway.vote",
            sentryDsn: resolveSentryDsn(),
            // Where development errors go: the collector on the machine running the
            // dev server, never Sentry. mise.toml exports this from
            // config/rustrak_project.key, which bin/rustrak-provision writes. Absent
            // means errors stay in the console, which breaks nothing.
            rustrakDsn: process.env.RUSTRAK_DSN_MOBILE,
            // Google Places API key (Places API New). The key is restricted in
            // Google Cloud to the app's bundle id, so requests must include
            // X-Ios-Bundle-Identifier. Android requires a separate key (not yet
            // issued); AddressAutocomplete falls back to manual entry when the
            // key is missing for the current platform.
            googlePlacesApiKeyIOS: process.env.EXPO_PUBLIC_GOOGLE_PLACES_API_KEY_IOS,
            googlePlacesApiKeyAndroid: process.env.EXPO_PUBLIC_GOOGLE_PLACES_API_KEY_ANDROID,
        },
    });
};
