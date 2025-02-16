import OrganizationIcon from "app/frontend/components/organizations/OrganizationIcon";
import { Support } from "app/frontend/sway_constants";
import { Button, Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    organizationPosition: sway.IOrganizationPosition;
    organizationsCount: number;
    organization: sway.IOrganizationBase;
    supportSelected: number;
    opposeSelected: number;
    setSupportSelected: React.Dispatch<React.SetStateAction<number>>;
    setOpposeSelected: React.Dispatch<React.SetStateAction<number>>;
    index: number;
}

const BillArgumentsOrganization: React.FC<IProps> = ({
    organizationPosition,
    organizationsCount,
    organization,
    supportSelected,
    opposeSelected,
    setSupportSelected,
    setOpposeSelected,
    index,
}) => {
    const handler =
        organizationPosition.support === Support.For ? () => setSupportSelected(index) : () => setOpposeSelected(index);
    const isSelected =
        organizationPosition.support === Support.For ? supportSelected === index : opposeSelected === index;

    return (
        <div className={`col-${organizationsCount ? 12 / organizationsCount : "auto"} text-center p-2`}>
            <Button
                variant="link"
                onClick={handler}
                // corner-circle - https://stackoverflow.com/a/58700914/6410635
                className={isSelected ? "corner-circle text-primary no-underline" : "no-underline"}
            >
                {organization?.iconPath ? (
                    <OrganizationIcon organization={organization} maxWidth={100} />
                ) : (
                    <Image
                        src={
                            organizationPosition.support === Support.For
                                ? "/images/thumbs-up.svg"
                                : "/images/thumbs-down.svg"
                        }
                        style={{
                            maxWidth: "150px",
                        }}
                    />
                )}
            </Button>
        </div>
    );
};

export default BillArgumentsOrganization;
