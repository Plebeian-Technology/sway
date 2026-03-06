from fetch_law import fetch_and_convert_law
from fetch_bills import fetch_and_process_bills

def main():
    print("Step 1: Fetching and converting Charter and Code...")
    fetch_and_convert_law()

    print("\nStep 2: Fetching and processing Bills...")
    fetch_and_process_bills()

    print("\nDone.")

if __name__ == "__main__":
    main()
