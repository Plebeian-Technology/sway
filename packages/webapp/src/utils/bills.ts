import { Timestamp } from "firebase/firestore";
import { sway } from "sway";

export const getCreatedAt = (b: sway.IBill) => {
    if (!b.createdAt) return new Date();
    if (b.createdAt instanceof Date) {
        return b.createdAt;
    } else if (typeof b.createdAt === "string") {
        return new Date(b.createdAt);
    } else if (typeof b.createdAt === "object" && "seconds" in b.createdAt) {
        return new Date(Number((b.createdAt as { seconds: number }).seconds * 1000));
    } else {
        return (b.createdAt as Timestamp)?.toDate();
    }
};
