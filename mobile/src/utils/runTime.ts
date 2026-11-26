export const parseTime = (iso: string | null | undefined) => {
    const date = iso?.trim() ? new Date(iso.trim()) : null;
    return date && !isNaN(date.getTime()) ? date : null;
};

export const exactTime = (iso: string | null | undefined) => {
    const date = parseTime(iso);
    if (!date) return null;
    const day = date.toLocaleDateString("en-US", { month: "long", day: "2-digit", year: "numeric" });
    const time = date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: true });
    return `${day} at ${time}`;
};

export const relativeTime = (date: Date) => {
    const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
    if (seconds < 0) return "just now";
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
};
