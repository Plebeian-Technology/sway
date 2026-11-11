// @lat: [[mobile-chrome-sheets-design#AccessibilityPolyfill]]
import React from "react";

export interface AccessibilityPolyfillProps {
    children: React.ReactNode;
}

export function AccessibilityPolyfill({ children }: AccessibilityPolyfillProps): React.JSX.Element {
    return <>{children}</>;
}

export default AccessibilityPolyfill;
