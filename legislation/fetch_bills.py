import requests
import os
import io
import re
from pypdf import PdfReader
from datetime import datetime

# Configuration
API_BASE = "https://webapi.legistar.com/v1/baltimore"
TARGET_DIR = "legislation/diffs"
MATTER_TYPES = ["Ordinance"] # We focus on Ordinances as they are laws
YEARS = [2025, 2026]

def get_ordinances():
    ordinances = []
    # Filter by date and type
    # OData filter for year is hard because MatterIntroDate is a full datetime.
    # We can fetch top N and filter in python, or use ge/le operators.
    # Since 2025 is the start, we can just say >= 2025-01-01.

    filter_query = "MatterIntroDate ge datetime'2025-01-01T00:00:00' and MatterTypeName eq 'Ordinance'"

    params = {
        "$filter": filter_query,
        "$orderby": "MatterIntroDate desc",
        "$top": 1000
    }

    print(f"Fetching ordinances from {API_BASE}/Matters...")
    try:
        response = requests.get(f"{API_BASE}/Matters", params=params)
        response.raise_for_status()
        data = response.json()
        print(f"Found {len(data)} ordinances.")
        return data
    except Exception as e:
        print(f"Error fetching ordinances: {e}")
        return []

def get_attachments(matter_id):
    try:
        response = requests.get(f"{API_BASE}/Matters/{matter_id}/Attachments")
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"Error fetching attachments for {matter_id}: {e}")
        return []

def download_pdf(url):
    try:
        response = requests.get(url)
        response.raise_for_status()
        return io.BytesIO(response.content)
    except Exception as e:
        print(f"Error downloading PDF {url}: {e}")
        return None

def extract_text_from_pdf(pdf_file):
    try:
        reader = PdfReader(pdf_file)
        text = ""
        for page in reader.pages:
            text += page.extract_text() + "\n"
        return text
    except Exception as e:
        print(f"Error extracting text from PDF: {e}")
        return ""

def extract_summary(text):
    # Look for "FOR the purpose of..."
    # Usually starts with "FOR the purpose of" and ends with a semicolon or period before "BY repealing" or similar sections?
    # Or just the first paragraph starting with that phrase.

    match = re.search(r"(FOR the purpose of.*?)(\n\s*[A-Z][A-Z]+|\Z)", text, re.DOTALL | re.IGNORECASE)
    if match:
        summary = match.group(1)
        # Clean up whitespace
        summary = re.sub(r'\s+', ' ', summary).strip()
        return summary
    return "Summary not found."

def determine_context(text):
    if "City Charter" in text:
        return "Baltimore City Charter"
    return "Baltimore City Code"

def fetch_and_process_bills():
    if not os.path.exists(TARGET_DIR):
        os.makedirs(TARGET_DIR)

    ordinances = get_ordinances()

    for ord in ordinances:
        matter_id = ord['MatterId']
        file_id = ord['MatterFile']
        title = ord['MatterTitle']
        intro_date = ord['MatterIntroDate']

        print(f"Processing {file_id}: {title[:50]}...")

        # Get attachments to find PDF
        attachments = get_attachments(matter_id)
        pdf_url = None
        # Look for the bill text attachment. Usually contains the file ID or "Text".
        # Sort by MatterAttachmentLastModifiedUtc desc to get latest?

        # Heuristic: Prefer "Bill" or "Ordinance" in name, or just take the first PDF.
        for att in attachments:
            if att['MatterAttachmentFileName'].lower().endswith('.pdf'):
                pdf_url = att['MatterAttachmentHyperlink']
                break

        if pdf_url:
            print(f"  Downloading PDF: {pdf_url}")
            pdf_data = download_pdf(pdf_url)
            if pdf_data:
                text = extract_text_from_pdf(pdf_data)

                # Save as markdown/text
                md_filename = os.path.join(TARGET_DIR, f"{file_id}.md")
                with open(md_filename, "w") as f:
                    f.write(text)

                # Summary
                summary = extract_summary(text)
                context = determine_context(text)

                summary_filename = os.path.join(TARGET_DIR, f"{file_id}_summary.txt")
                with open(summary_filename, "w") as f:
                    f.write(f"Context: {context}\n\nSummary:\n{summary}\n")

                print(f"  Saved markdown and summary for {file_id}")
        else:
            print(f"  No PDF found for {file_id}")

if __name__ == "__main__":
    fetch_and_process_bills()
