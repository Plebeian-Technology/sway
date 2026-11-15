// Pin the test timezone BEFORE anything else evaluates. Screens render dates
// via toLocaleDateString(), which reads the process zone at first Intl use —
// snapshots written on one machine failed on another (UTC vs Eastern:
// PasskeyManagementScreen's "Created 1/15/2026" rendered 1/14 west of UTC).
// This must live in the config (not a setupFiles entry): the config evaluates
// in the main jest process before ICU resolves a zone, and spawned workers
// inherit the env.
process.env.TZ = "UTC";

const { readFileSync } = require("node:fs");
const { relative, resolve } = require("node:path");

// @lat: [[verification-gates#Mobile onboarding coverage gate]]
const onboardingFloors = JSON.parse(
    readFileSync(resolve(__dirname, "../config/onboarding_coverage_floor.mobile.json"), "utf8"),
);
const onboardingFiles = Object.keys(onboardingFloors).map((file) =>
    relative(__dirname, resolve(__dirname, "..", file)),
);

// jest-expo preset already wires babel-jest + react-native env. Override the
// transformIgnorePatterns so pnpm-mangled paths under .pnpm/ still get
// transformed for the RN/Expo/NativeWind/etc. ecosystem (default RN regex assumes
// flat node_modules, not pnpm's nested .pnpm/<id>/node_modules layout).
module.exports = {
    preset: "jest-expo",
    setupFilesAfterEnv: ["<rootDir>/jest.setup.ts"],
    // @lat: [[toolchain-pins#Toolchain pins#Why the frontend suite refuses to start under the wrong Node]]
    globalSetup: "<rootDir>/jest.global-setup.js",
    moduleFileExtensions: ["ts", "tsx", "js", "jsx", "json"],
    // @lat: [[mobile-expo-config#The Expo config file and the mobile type check#What the mobile test environment has to stand in for]]
    watchman: false,
    // Force module resolution to the mobile pnpm node_modules rather than
    // traversing up to the monorepo root (which has a different React copy).
    // Required when running from a git worktree where ../../../../node_modules
    // would otherwise be found first and cause duplicate-React hook errors.
    // <rootDir> (this config's directory) keeps the anchor portable — a
    // hardcoded absolute path here broke every suite on CI runners.
    modulePaths: ["<rootDir>/node_modules"],
    moduleNameMapper: {
        // NativeWind processes global.css at native build time via metro;
        // jest-runtime would otherwise try to parse it as JavaScript.
        "\\.css$": "<rootDir>/__mocks__/styleMock.js",
        // Anchor react + react-native to the mobile pnpm copies to prevent
        // hook-count errors from dual-React in git worktree context. The
        // node_modules/react symlink resolves into mobile's own .pnpm store,
        // so this pins the same copy without hardcoding machine or version.
        "^react$": "<rootDir>/node_modules/react",
        "^react/(.*)$": "<rootDir>/node_modules/react/$1",
    },
    transformIgnorePatterns: [
        "node_modules/(?!.*(?:(?:jest-)?react-native|@react-native|@react-navigation|expo(?:nent)?|@expo|@unimodules|unimodules|sentry-expo|nativewind|react-native-css-interop|@rails/actioncable|react-native-url-polyfill|react-native-reanimated|@sentry/react-native|lucide-react-native|mdast-util-[^/]+|micromark[^/]*|unist-util-[^/]+|decode-named-character-reference|character-entities|ccount|devlop|markdown-table|escape-string-regexp|longest-streak|zwitch))",
    ],
    testMatch: ["**/__tests__/**/*.test.(ts|tsx)", "**/__tests__/**/*.spec.(ts|tsx)"],
    testPathIgnorePatterns: ["/node_modules/"],
    collectCoverageFrom: onboardingFiles,
    coverageReporters: ["text"],
    coverageThreshold: Object.fromEntries(
        Object.entries(onboardingFloors).map(([file, floor]) => [
            resolve(__dirname, "..", file),
            { lines: floor.line, branches: floor.branch },
        ]),
    ),
};
