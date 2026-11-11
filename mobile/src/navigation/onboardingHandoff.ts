// @lat: [[mobile-auth-and-onboarding-flow#onboardingHandoff]]
let pending = false;

export const onboardingHandoff = {
    setLandOnLegislators(): void {
        pending = true;
    },
    consumeLandOnLegislators(): boolean {
        const v = pending;
        pending = false;
        return v;
    },
};
