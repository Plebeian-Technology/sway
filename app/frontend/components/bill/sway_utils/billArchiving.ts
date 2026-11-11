// @lat: [[bill-session-archiving#Why Bills of the Month are never archived]]
export interface IArchivableBill {
    active?: boolean;
    scheduled_release_date_utc?: string | null;
}

export const isArchivedHistoricalBill = (bill?: IArchivableBill | null): boolean =>
    bill?.active === false && !bill?.scheduled_release_date_utc;
