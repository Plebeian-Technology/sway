import { ButtonProps, Button } from "react-bootstrap";

const NavLinkButton = ({
    isSelected,
    variant: _variant,
    children,
    ...props
}: ButtonProps & { isSelected: boolean }) => {
    return (
        <Button
            {...props}
            variant={isSelected ? "primary" : "outline-secondary"}
            className={"align-middle fs-5 align-items-center text-start py-2 px-3 my-1 border-0"}
        >
            {children}
        </Button>
    );
};

export default NavLinkButton;
