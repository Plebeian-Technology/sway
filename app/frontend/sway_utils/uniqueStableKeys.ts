// @lat: [[unique-stable-keys-react-list-identity#draftOrgPositionKeys]]
export const uniqueStableKeys = (identities: string[]): string[] => {
    const seen = new Map<string, number>();

    return identities.map((identity) => {
        const occurrence = seen.get(identity) ?? 0;
        seen.set(identity, occurrence + 1);
        return `${identity}#${occurrence}`;
    });
};
