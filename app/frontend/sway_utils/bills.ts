import { sway } from "sway";

export const toSelectLabelFromBill = (bill: sway.IBill) => `${bill.external_id} - ${bill.title}`;
