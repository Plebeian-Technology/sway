// @lat: [[mobile-expo-config#The Expo config file and the mobile type check#Why native handover happens in an effect, not at module scope]]
import "react-native-url-polyfill/auto";

// oxlint-disable-next-line @typescript-eslint/no-empty-function
global.addEventListener = global.addEventListener || (() => {});
// oxlint-disable-next-line @typescript-eslint/no-empty-function
global.removeEventListener = global.removeEventListener || (() => {});

import { registerRootComponent } from "expo";
import App from "./App";
import { initSentry } from "./src/observability/sentry";

initSentry();
registerRootComponent(App);
