// @lat: [[bill-creator-landed-write-detection#Why the landing page, not the callback]]
export const landedOnBillCreator = (url: string, billId: number): boolean => {
    const base = `/admin/bill_creator/${billId}`;
    if (!url.startsWith(base)) return false;

    const next = url.charAt(base.length);
    return next === "" || next === "/" || next === "?" || next === "#";
};
