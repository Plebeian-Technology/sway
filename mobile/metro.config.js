const path = require("path");
const { getSentryExpoConfig } = require("@sentry/react-native/metro");
const { withNativeWind } = require("nativewind/metro");

const projectRoot = __dirname;
const monorepoRoot = path.resolve(projectRoot, "..");

// @lat: [[mobile-sentry-init-design#Why the Metro config comes from Sentry]]
const config = getSentryExpoConfig(projectRoot);

// Phase 36 (D-13/14/15): mobile screens consume PARITY_COPY from
// app/frontend/sway_constants/parityCopy.ts as the cross-platform copy
// source-of-truth. Metro must watch the parent dir + resolve modules from
// the mobile workspace's node_modules.
config.watchFolders = [path.resolve(projectRoot, "../app/frontend")];
config.resolver.nodeModulesPaths = [path.resolve(projectRoot, "node_modules")];

module.exports = withNativeWind(config, { input: "./global.css" });
