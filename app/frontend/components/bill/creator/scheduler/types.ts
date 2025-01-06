import { IParams } from "app/frontend/hooks/useSearchParams";
import React from "react";
import { ISelectOption, sway } from "sway";

export interface IBillScheduleProps {
    params: IParams;
    selectedBill: ISelectOption;
    setSelectedBill: (o: ISelectOption, params?: Record<string, string>) => void;
}

export interface IBillScheduleCalendarProps extends IBillScheduleProps {
    selectedDate: Date | null;
    setSelectedDate: React.Dispatch<React.SetStateAction<Date | null>>;
    handleSelectBill: (bill: sway.IBill, newParams?: Record<string, string>) => void;
}
