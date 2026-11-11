// @lat: [[mobile-a11y-announce-hook#Privacy]]
import { AccessibilityInfo } from "react-native";

export type A11yAnnouncer = (message: string) => void;

export function useA11yAnnounce(): A11yAnnouncer {
    return (message: string) => {
        AccessibilityInfo.announceForAccessibility(message);
    };
}

export default useA11yAnnounce;
