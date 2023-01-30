if (!Array.prototype.first) {
    Array.prototype.first = function () {
        return this[0];
    };
}

if (!Array.prototype.last) {
    Array.prototype.last = function () {
        return this[this.length - 1];
    };
}

export * from "./firebase";
export * from "./data";
export * from "./users";
export * from "./bills";
export * from "./legislators";
export * from "./organizations";
export * from "./google_sheets";
