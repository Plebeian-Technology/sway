export function formatEta(seconds: number | null | undefined): string {
    if (seconds === null || seconds === undefined) return "";
    if (seconds < 60) return `${seconds}s`;
    const hours = Math.floor(seconds / 3600);
    const totalMins = Math.floor(seconds / 60);
    const remainingMins = Math.floor((seconds % 3600) / 60);
    const remainingSecs = seconds % 60;
    if (seconds < 3600) {
        return `${totalMins}m ${remainingSecs}s`;
    }
    return `${hours}h ${remainingMins}m`;
}
