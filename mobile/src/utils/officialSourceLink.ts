// @lat: [[unlinked-bill-presentation#Separation of URL safety from link validity]]
import * as WebBrowser from "expo-web-browser";

import { getOfficialSourceHosts, isSafeBillLink } from "../constants/officialSourceHosts";

export function isOnOfficialSourceHost(
    link: string | null | undefined,
    swayLocaleSlug?: string,
    allowedSourceHosts?: readonly string[],
): boolean {
    return isSafeBillLink(link, getOfficialSourceHosts(swayLocaleSlug, allowedSourceHosts));
}

export function openSourceLink(link: string): void {
    void WebBrowser.openBrowserAsync(link, {
        dismissButtonStyle: "done",
        showTitle: true,
        enableDefaultShareMenuItem: true,
    }).catch(() => undefined);
}
