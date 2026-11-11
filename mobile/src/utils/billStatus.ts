// @lat: [[mobile-bill-surface-components-design#BillHeader]]
import { swayTokens, type SwayColorScheme } from "../theme/tokens";

const STATUS_TOKENS: Record<string, "success" | "destructive" | "warning"> = {
    passed: "success",
    failed: "destructive",
    vetoed: "destructive",
    committee: "warning",
};

export const billStatusColor = (status?: string | null, colorScheme: SwayColorScheme = "light"): string | null => {
    if (!status) return null;
    const palette = swayTokens[colorScheme];
    const token = STATUS_TOKENS[status.toLowerCase()];
    return token ? palette[token] : palette.mutedForeground;
};

export const billStatusLabel = (status: string): string => status.charAt(0).toUpperCase() + status.slice(1);
