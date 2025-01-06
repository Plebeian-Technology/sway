import { sway } from "sway";

export const toSelectLabelFromBill = (bill: sway.IBill) => `${bill.externalId} - ${bill.title}`;
