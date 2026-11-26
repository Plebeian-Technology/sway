import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

const mockSetParams = jest.fn();
jest.mock("@react-navigation/native", () => ({
    useNavigation: () => ({ setParams: mockSetParams }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import ScheduleTab from "../../../../src/screens/admin/billCreator/tabs/ScheduleTab";

const bills = [
    { id: 1, external_id: "HB1", title: "One", scheduled_release_date_utc: null },
    { id: 2, external_id: "HB2", title: "Two", scheduled_release_date_utc: null },
];

// @lat: [[mobile-bill-creator#Sections#The schedule section]]
describe("ScheduleTab", () => {
    beforeEach(() => jest.clearAllMocks());

    it("switches the screen to the bill that is pressed in the lists", () => {
        render(
            <ScheduleTab
                billId={1}
                data={{ bill: { id: 1, external_id: "HB1", title: "One" }, bills }}
                refresh={jest.fn()}
            />,
        );

        fireEvent.press(screen.getByTestId("admin-schedule-unscheduled-toggle"));
        fireEvent.press(screen.getByTestId("admin-schedule-row-2"));

        expect(mockSetParams).toHaveBeenCalledWith({ billId: 2 });
    });
});
