import React from "react";
import { act, fireEvent, render, screen } from "@testing-library/react-native";
import GooglePlacesSDK from "react-native-google-places-sdk";

import AddressAutocomplete from "../../src/components/AddressAutocomplete";

jest.mock("react-native-google-places-sdk", () => ({
    __esModule: true,
    default: {
        fetchPredictions: jest.fn(),
        fetchPlaceByID: jest.fn(),
        initialize: jest.fn(),
    },
    PLACE_FIELDS: {
        ADDRESS_COMPONENTS: "ADDRESS_COMPONENTS",
        FORMATTED_ADDRESS: "FORMATTED_ADDRESS",
        COORDINATE: "COORDINATE",
        TYPES: "TYPES",
    },
}));

const mockFetchPredictions = GooglePlacesSDK.fetchPredictions as jest.Mock;
const mockFetchPlaceByID = GooglePlacesSDK.fetchPlaceByID as jest.Mock;

const prediction = {
    placeID: "PLACE_1",
    primaryText: "100 N Holliday St",
    secondaryText: "Baltimore, MD, USA",
    description: "100 N Holliday St, Baltimore, MD, USA",
};

const street = [
    { types: ["street_number"], name: "100", shortName: "100" },
    { types: ["route"], name: "N Holliday St", shortName: "N Holliday St" },
];
const locality = { types: ["locality"], name: "Baltimore", shortName: "Baltimore" };
const state = { types: ["administrative_area_level_1"], name: "Maryland", shortName: "MD" };
const postalCode = { types: ["postal_code"], name: "21202", shortName: "21202" };
const country = { types: ["country"], name: "United States", shortName: "US" };
const coordinate = { latitude: 39.29105, longitude: -76.61069 };

const typeQuery = async (text: string) => {
    fireEvent.changeText(screen.getByTestId("address-autocomplete-input"), text);
    await act(async () => {
        jest.advanceTimersByTime(250);
    });
};

const typeAndPick = async () => {
    await typeQuery("100 N Holliday");
    fireEvent.press(await screen.findByTestId("address-suggestion-PLACE_1"));
    await act(async () => {});
};

describe("AddressAutocomplete", () => {
    const onSelect = jest.fn();
    const onError = jest.fn();

    const renderComponent = () => render(<AddressAutocomplete onSelect={onSelect} onError={onError} />);

    beforeEach(() => {
        jest.useFakeTimers();
        jest.clearAllMocks();
        mockFetchPredictions.mockResolvedValue([prediction]);
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    // @lat: [[mobile-address-autocomplete-design#selectedDescription reopen guard]]
    it("makes no search on mount for a saved address and searches once the user edits it", async () => {
        render(
            <AddressAutocomplete initialValue="100 N Holliday St, Baltimore" onSelect={onSelect} onError={onError} />,
        );

        await act(async () => {
            jest.advanceTimersByTime(1000);
        });
        expect(mockFetchPredictions).not.toHaveBeenCalled();
        expect(screen.queryByTestId("address-suggestion-PLACE_1")).toBeNull();
        expect(onError).not.toHaveBeenCalled();

        await typeQuery("100 N Holliday St, Baltimore 2");

        expect(mockFetchPredictions).toHaveBeenCalledTimes(1);
        expect(screen.getByTestId("address-suggestion-PLACE_1")).toBeTruthy();
    });

    it("tells the user to type the address when the search is refused", async () => {
        mockFetchPredictions.mockRejectedValue(new Error("PERMISSION_DENIED api key not authorized"));
        renderComponent();

        await typeQuery("100 N Holliday");

        expect(onError).toHaveBeenCalledTimes(1);
        expect(onError).toHaveBeenCalledWith(expect.stringContaining("Edit address fields manually"));
        expect(onError.mock.calls[0][0]).not.toMatch(/PERMISSION_DENIED/);
    });

    it("shows a fixed sentence when the details lookup fails", async () => {
        mockFetchPlaceByID.mockRejectedValue(new Error("OVER_QUERY_LIMIT quota exceeded"));
        renderComponent();

        await typeAndPick();

        expect(onError).toHaveBeenCalledTimes(1);
        expect(onError.mock.calls[0][0]).not.toMatch(/OVER_QUERY_LIMIT/);
        expect(onSelect).not.toHaveBeenCalled();
    });

    it("passes on a place with no coordinate and no postal code", async () => {
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, state, country],
            formattedAddress: "100 N Holliday St, Baltimore, MD, USA",
            types: ["street_address"],
        });
        renderComponent();

        await typeAndPick();

        expect(onSelect).toHaveBeenCalledTimes(1);
        expect(onSelect).toHaveBeenCalledWith(
            expect.objectContaining({ street1: "100 N Holliday St", postal_code: "", latitude: null, longitude: null }),
        );
        expect(onError).not.toHaveBeenCalled();
    });

    it("passes on a place with a coordinate but no locality", async () => {
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, state, postalCode, country],
            coordinate,
        });
        renderComponent();

        await typeAndPick();

        expect(onSelect).toHaveBeenCalledWith(
            expect.objectContaining({ city: "", region_code: "MD", latitude: coordinate.latitude }),
        );
        expect(onError).not.toHaveBeenCalled();
    });

    it("passes on a place with a coordinate but no state", async () => {
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, postalCode, country],
            coordinate,
        });
        renderComponent();

        await typeAndPick();

        expect(onSelect).toHaveBeenCalledWith(
            expect.objectContaining({ city: "Baltimore", region_code: "", longitude: coordinate.longitude }),
        );
        expect(onError).not.toHaveBeenCalled();
    });

    it("parses a complete place", async () => {
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, state, postalCode, country],
            coordinate,
            formattedAddress: "100 N Holliday St, Baltimore, MD 21202, USA",
            types: ["street_address", "geocode"],
        });
        renderComponent();

        await typeAndPick();

        expect(onSelect).toHaveBeenCalledTimes(1);
        expect(onSelect).toHaveBeenCalledWith({
            street1: "100 N Holliday St",
            street2: "",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202",
            country: "US",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            formatted: "100 N Holliday St, Baltimore, MD 21202, USA",
            place_types: ["street_address", "geocode"],
        });
    });

    it("passes the ISO country code when the device language localizes the country name", async () => {
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [
                ...street,
                locality,
                state,
                postalCode,
                { types: ["country"], name: "Estados Unidos", shortName: "US" },
            ],
            coordinate,
        });
        renderComponent();

        await typeAndPick();

        expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ country: "US" }));
    });

    it("falls back to United States when the place has no country component", async () => {
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, state, postalCode],
            coordinate,
        });
        renderComponent();

        await typeAndPick();

        expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ country: "United States" }));
    });

    it("ignores the response of an earlier query once a newer one is sent", async () => {
        let resolveFirst: (value: unknown[]) => void = () => {};
        mockFetchPredictions
            .mockImplementationOnce(() => new Promise((resolve) => (resolveFirst = resolve)))
            .mockResolvedValueOnce([]);
        renderComponent();

        await typeQuery("100 N Holl");
        await typeQuery("100 N Holliday");
        await act(async () => resolveFirst([prediction]));

        expect(screen.queryByTestId("address-suggestion-PLACE_1")).toBeNull();
    });

    it("ignores a failure of an earlier query once a newer one is sent", async () => {
        let rejectFirst: (reason: Error) => void = () => {};
        mockFetchPredictions
            .mockImplementationOnce(() => new Promise((_resolve, reject) => (rejectFirst = reject)))
            .mockResolvedValueOnce([prediction]);
        renderComponent();

        await typeQuery("100 N Holl");
        await typeQuery("100 N Holliday");
        await act(async () => rejectFirst(new Error("late failure")));

        expect(onError).not.toHaveBeenCalled();
    });

    it("does not overwrite a newer search when the details of a picked place arrive late", async () => {
        let resolvePlace: (value: unknown) => void = () => {};
        mockFetchPlaceByID.mockImplementationOnce(() => new Promise((resolve) => (resolvePlace = resolve)));
        mockFetchPredictions.mockResolvedValueOnce([prediction]).mockResolvedValueOnce([]);
        renderComponent();

        await typeQuery("100 N Holliday");
        fireEvent.press(await screen.findByTestId("address-suggestion-PLACE_1"));
        await typeQuery("200 S Charles St");
        await act(async () =>
            resolvePlace({ addressComponents: [...street, locality, state, postalCode, country], coordinate }),
        );

        expect(onSelect).not.toHaveBeenCalled();
        expect(onError).not.toHaveBeenCalled();
    });

    it("reports no details failure for a picked place once a newer search has started", async () => {
        let rejectPlace: (reason: Error) => void = () => {};
        mockFetchPlaceByID.mockImplementationOnce(() => new Promise((_resolve, reject) => (rejectPlace = reject)));
        mockFetchPredictions.mockResolvedValueOnce([prediction]).mockResolvedValueOnce([]);
        renderComponent();

        await typeQuery("100 N Holliday");
        fireEvent.press(await screen.findByTestId("address-suggestion-PLACE_1"));
        await typeQuery("200 S Charles St");
        await act(async () => rejectPlace(new Error("late failure")));

        expect(onError).not.toHaveBeenCalled();
    });

    it("ignores a response that arrives after a suggestion was picked", async () => {
        let resolveLate: (value: unknown[]) => void = () => {};
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, state, postalCode, country],
            coordinate,
        });
        mockFetchPredictions
            .mockResolvedValueOnce([prediction])
            .mockImplementationOnce(() => new Promise((resolve) => (resolveLate = resolve)));
        renderComponent();

        await typeQuery("100 N Holliday");
        const suggestion = await screen.findByTestId("address-suggestion-PLACE_1");
        await typeQuery("100 N Holliday St");
        fireEvent.press(suggestion);
        await act(async () => {});
        await act(async () => resolveLate([prediction]));

        expect(onSelect).toHaveBeenCalledTimes(1);
        expect(screen.queryByTestId("address-suggestion-PLACE_1")).toBeNull();
    });

    it("ignores a failure that arrives after a suggestion was picked", async () => {
        let rejectLate: (reason: Error) => void = () => {};
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, state, postalCode, country],
            coordinate,
        });
        mockFetchPredictions
            .mockResolvedValueOnce([prediction])
            .mockImplementationOnce(() => new Promise((_resolve, reject) => (rejectLate = reject)));
        renderComponent();

        await typeQuery("100 N Holliday");
        const suggestion = await screen.findByTestId("address-suggestion-PLACE_1");
        await typeQuery("100 N Holliday St");
        fireEvent.press(suggestion);
        await act(async () => {});
        await act(async () => rejectLate(new Error("late failure")));

        expect(onSelect).toHaveBeenCalledTimes(1);
        expect(onError).not.toHaveBeenCalled();
    });

    // @lat: [[mobile-address-autocomplete-design#Editing the search text clears the form]]
    it("reports each edit of the text through onQueryChange and not the text of a pick", async () => {
        const onQueryChange = jest.fn();
        mockFetchPlaceByID.mockResolvedValue({
            addressComponents: [...street, locality, state, postalCode, country],
            coordinate,
        });
        render(<AddressAutocomplete onSelect={onSelect} onError={onError} onQueryChange={onQueryChange} />);

        await typeQuery("100 N Holliday");
        expect(onQueryChange).toHaveBeenCalledTimes(1);
        expect(onQueryChange).toHaveBeenLastCalledWith("100 N Holliday");

        fireEvent.press(await screen.findByTestId("address-suggestion-PLACE_1"));
        await act(async () => {});

        expect(onSelect).toHaveBeenCalledTimes(1);
        expect(onQueryChange).toHaveBeenCalledTimes(1);
    });

    it("searches again when the user types the saved text back after editing it", async () => {
        const saved = "100 N Holliday St, Baltimore";
        render(<AddressAutocomplete initialValue={saved} onSelect={onSelect} onError={onError} />);

        await typeQuery(`${saved}2`);
        mockFetchPredictions.mockClear();
        await typeQuery(saved);

        expect(mockFetchPredictions).toHaveBeenCalledTimes(1);
        expect(screen.getByTestId("address-suggestion-PLACE_1")).toBeTruthy();
    });

    it("drops the details of a picked place when the user edits the text before they arrive", async () => {
        let resolvePlace: (value: unknown) => void = () => {};
        mockFetchPlaceByID.mockImplementationOnce(() => new Promise((resolve) => (resolvePlace = resolve)));
        renderComponent();

        await typeQuery("100 N Holliday");
        fireEvent.press(await screen.findByTestId("address-suggestion-PLACE_1"));
        fireEvent.changeText(screen.getByTestId("address-autocomplete-input"), "1");
        await act(async () =>
            resolvePlace({ addressComponents: [...street, locality, state, postalCode, country], coordinate }),
        );

        expect(onSelect).not.toHaveBeenCalled();
        expect(screen.queryByLabelText("Searching addresses")).toBeNull();
    });

    it("makes no SDK call for fewer than three characters", async () => {
        renderComponent();

        await typeQuery("10");

        expect(mockFetchPredictions).not.toHaveBeenCalled();
    });
});
