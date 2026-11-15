import { describe, expect, it } from "vitest";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { formatCountdown, secondsUntil } from "app/frontend/sway_utils/resendCooldown";

// @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown clock on Send a new code]]
describe("resend cooldown clock", () => {
    it("writes a wait under an hour as minutes and two-digit seconds", () => {
        expect(formatCountdown(60)).toBe("1:00");
        expect(formatCountdown(42)).toBe("0:42");
        expect(formatCountdown(307)).toBe("5:07");
        expect(formatCountdown(0)).toBe("0:00");
    });

    it("writes a daily-limit wait with hours", () => {
        expect(formatCountdown(71_400)).toBe("19:50:00");
        expect(formatCountdown(3_661)).toBe("1:01:01");
    });

    it("rounds a partial second up and never goes below zero", () => {
        expect(secondsUntil(10_500, 10_000)).toBe(1);
        expect(secondsUntil(10_000, 12_000)).toBe(0);
        expect(secondsUntil(null, 0)).toBe(0);
    });

    it("words the spoken wait in seconds, minutes, or hours", () => {
        const wait = PARITY_COPY.auth.passkeyPanel.resendCodeWait;
        expect(wait(1)).toBe("You can send a new code in 1 second.");
        expect(wait(42)).toBe("You can send a new code in 42 seconds.");
        expect(wait(60)).toBe("You can send a new code in 1 minute.");
        expect(wait(307)).toBe("You can send a new code in 6 minutes.");
        expect(wait(71_400)).toBe("You can send a new code in about 20 hours.");
        expect(PARITY_COPY.auth.passkeyPanel.resendCodeIn("0:42")).toBe("Send a new code in 0:42");
    });
});
