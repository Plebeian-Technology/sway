import type { RouteProp } from "@react-navigation/native";

import { isTopLevelRouteFocused } from "../../src/navigation/AppDrawer";
import type { AppDrawerParamList } from "../../src/navigation/types";

type DrawerRoute = RouteProp<AppDrawerParamList>;

const route = (fields: Record<string, unknown>): DrawerRoute =>
    ({ key: "Bills-key", name: "Bills", ...fields }) as unknown as DrawerRoute;

// @lat: [[mobile-tab-navigation-architecture#AppDrawer#Edge swipe opens the drawer only on top level screens]]
describe("isTopLevelRouteFocused", () => {
    it("treats a route with no nested state as top level", () => {
        expect(isTopLevelRouteFocused(route({}))).toBe(true);
    });

    it("treats a stack focused on BillsList as top level", () => {
        const state = { index: 0, routes: [{ key: "BillsList-key", name: "BillsList" }] };
        expect(isTopLevelRouteFocused(route({ state }))).toBe(true);
    });

    it("treats a pushed BillDetail route as not top level", () => {
        const state = {
            index: 1,
            routes: [
                { key: "BillsList-key", name: "BillsList" },
                { key: "BillDetail-key", name: "BillDetail" },
            ],
        };
        expect(isTopLevelRouteFocused(route({ state }))).toBe(false);
    });

    it("treats a deep link to BillDetail as not top level before the stack has state", () => {
        expect(isTopLevelRouteFocused(route({ params: { screen: "BillDetail" } }))).toBe(false);
    });
});
