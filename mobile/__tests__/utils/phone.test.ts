/**
 // @lat: [[mobile-phone-formatting-parity#Why mobile's phone formatter is tested against the web copy]]
 */
import { formatPhone, isValidPhoneNumber, PHONE_INPUT_TRANSFORMER, removeNonDigits } from "../../src/utils/phone";

describe("removeNonDigits", () => {
    test("strips letters, parens, spaces, dashes", () => {
        expect(removeNonDigits("(410) 555-1234")).toBe("4105551234");
        expect(removeNonDigits("abc 410 555 def")).toBe("410555");
    });
    test("returns empty for null/undefined/empty", () => {
        expect(removeNonDigits(null)).toBe("");
        expect(removeNonDigits(undefined)).toBe("");
        expect(removeNonDigits("")).toBe("");
    });
});

describe("formatPhone", () => {
    test.each([
        ["", ""],
        ["4", "(4"],
        ["410", "(410"],
        ["4105", "(410) 5"],
        ["410555", "(410) 555"],
        ["4105551", "(410) 555 - 1"],
        ["4105551234", "(410) 555 - 1234"],
    ])("formats %s as %s", (input, expected) => {
        expect(formatPhone(input)).toBe(expected);
    });
});

describe("PHONE_INPUT_TRANSFORMER", () => {
    test("input formats raw digits", () => {
        expect(PHONE_INPUT_TRANSFORMER.input("4105551234")).toBe("(410) 555 - 1234");
    });
    test("input strips leading 1 country code (11 digits)", () => {
        expect(PHONE_INPUT_TRANSFORMER.input("14105551234")).toBe("(410) 555 - 1234");
    });
    test("output extracts digits, caps at 10", () => {
        expect(PHONE_INPUT_TRANSFORMER.output("(410) 555 - 1234")).toBe("4105551234");
        expect(PHONE_INPUT_TRANSFORMER.output("4105551234567")).toBe("4105551234");
    });
    test("output strips letters from pasted input", () => {
        expect(PHONE_INPUT_TRANSFORMER.output("abc410def555ghi1234")).toBe("4105551234");
    });
    test("output strips leading 1 from 11-digit paste", () => {
        expect(PHONE_INPUT_TRANSFORMER.output("+1 (410) 555-1234")).toBe("4105551234");
    });
});

describe("isValidPhoneNumber", () => {
    test.each([
        ["4105551234", true],
        ["410555123", false], // too short
        ["41055512345", false], // too long; normally cut to 10 digits before it gets here
        ["0105551234", false], // leading 0
        ["1105551234", false], // leading 1
        ["", false],
        [null, false],
        [undefined, false],
    ])("isValidPhoneNumber(%s) === %s", (input, expected) => {
        expect(isValidPhoneNumber(input)).toBe(expected);
    });
});
