export interface IDataOrganizationPositions {
    [organizationName: string]: {
        support?: boolean;
        position: string;
        label: string;
        value: string;
    };
}
