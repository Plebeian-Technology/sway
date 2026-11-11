// @lat: [[json-pointer-offset-resolution#resolveJsonPointerOffset]]
export const resolveJsonPointerOffset = (jsonText: string, pointer: string): number | null => {
    if (!pointer || pointer === "/") return 0;
    let parsed: unknown;
    try {
        parsed = JSON.parse(jsonText);
    } catch {
        return null;
    }
    const rawSegments = pointer.startsWith("/") ? pointer.slice(1).split("/") : pointer.split("/");
    const segments = rawSegments.map((seg) => seg.replace(/~1/g, "/").replace(/~0/g, "~"));

    // @lat: [[json-pointer-offset-resolution#Parent container tracking and approximate key lookup]]
    let parent: unknown = null;
    let cursor: unknown = parsed;
    for (const seg of segments) {
        if (Array.isArray(cursor)) {
            const idx = Number(seg);
            if (!Number.isInteger(idx) || idx < 0 || idx >= cursor.length) return null;
            parent = cursor;
            cursor = cursor[idx];
        } else if (cursor !== null && typeof cursor === "object") {
            const obj = cursor as Record<string, unknown>;
            if (!Object.prototype.hasOwnProperty.call(obj, seg)) return null;
            parent = cursor;
            cursor = obj[seg];
        } else {
            return null;
        }
    }

    // @lat: [[json-pointer-offset-resolution#Parent container tracking and approximate key lookup]]
    const lastSeg = segments[segments.length - 1];
    if (lastSeg === undefined) return null;
    const isArrayIndex = Array.isArray(parent) && /^\d+$/.test(lastSeg);
    if (isArrayIndex) {
        // @lat: [[json-pointer-offset-resolution#Parent container tracking and approximate key lookup]]
        const parentSeg = segments[segments.length - 2];
        if (parentSeg === undefined) return null;
        const parentNeedle = `"${parentSeg.replace(/"/g, '\\"')}"`;
        const parentAt = jsonText.indexOf(parentNeedle);
        return parentAt >= 0 ? parentAt : null;
    }
    const needle = `"${lastSeg.replace(/"/g, '\\"')}"`;
    const at = jsonText.indexOf(needle);
    return at >= 0 ? at : null;
};
