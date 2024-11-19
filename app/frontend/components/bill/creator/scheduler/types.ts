import { IParams } from "app/frontend/hooks/useSearchParams";
import { Dayjs } from "dayjs";
import React from "react";
import { ISelectOption, sway } from "sway";

export interface IBillScheduleProps {
    params: IParams;
    selectedBill: ISelectOption;
    setSelectedBill: (o: ISelectOption, params?: Record<string, string>) => void;
}

export interface IBillScheduleCalendarProps extends IBillScheduleProps {
    selectedDate: Dayjs | null;
    setSelectedDate: React.Dispatch<React.SetStateAction<Dayjs | null>>;
    handleSelectBill: (bill: sway.IBill, newParams?: Record<string, string>) => void;
}
