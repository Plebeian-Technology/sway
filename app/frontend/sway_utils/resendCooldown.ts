// @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown clock on Send a new code]]
export const RESEND_CODE_COOLDOWN_SECONDS = 60;

export const formatCountdown = (seconds: number): string => {
    const total = Math.max(0, Math.ceil(seconds));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const secs = String(total % 60).padStart(2, "0");
    return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${secs}` : `${minutes}:${secs}`;
};

export const secondsUntil = (untilMs: number | null, nowMs: number): number =>
    untilMs === null ? 0 : Math.max(0, Math.ceil((untilMs - nowMs) / 1000));
