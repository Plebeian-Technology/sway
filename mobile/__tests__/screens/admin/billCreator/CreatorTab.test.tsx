import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

const mockSetParams = jest.fn();
jest.mock("@react-navigation/native", () => ({
    useNavigation: () => ({ setParams: mockSetParams }),
}));

jest.mock("../../../../src/components/admin/billCreator/BillFieldsSection", () => {
    const { Pressable, Text } = jest.requireActual("react-native");
    return {
        __esModule: true,
        default: ({ onSaved }: { onSaved: (bill: { id: number }) => void }) => (
            <Pressable testID="bill-fields-save" onPress={() => onSaved({ id: 42 })}>
                <Text>Save</Text>
            </Pressable>
        ),
    };
});

import CreatorTab from "../../../../src/screens/admin/billCreator/tabs/CreatorTab";

// @lat: [[mobile-bill-creator#Sections#The bill fields section]]
describe("CreatorTab", () => {
    beforeEach(() => jest.clearAllMocks());

    it("switches the screen to a newly created bill's id", () => {
        const refresh = jest.fn();
        render(<CreatorTab billId={null} data={{ bill: undefined }} refresh={refresh} />);

        fireEvent.press(screen.getByTestId("bill-fields-save"));

        expect(mockSetParams).toHaveBeenCalledWith({ billId: 42 });
        expect(refresh).not.toHaveBeenCalled();
    });

    it("reloads the tab after an update", () => {
        const refresh = jest.fn().mockResolvedValue(undefined);
        render(<CreatorTab billId={42} data={{ bill: undefined }} refresh={refresh} />);

        fireEvent.press(screen.getByTestId("bill-fields-save"));

        expect(refresh).toHaveBeenCalled();
        expect(mockSetParams).not.toHaveBeenCalled();
    });
});
