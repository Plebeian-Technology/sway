import requests
import zipfile
import io
import os
import xml.etree.ElementTree as ET
import re

URL = "https://github.com/baltimore-legref/law-xml/archive/refs/heads/main.zip"
TEMP_DIR = "temp_law_xml_proc"
TARGET_DIR = "legislation"
CHARTER_PATH = os.path.join(TARGET_DIR, "baltimore_city_charter.md")
CODE_PATH = os.path.join(TARGET_DIR, "baltimore_city_code.md")

def download_and_extract_law():
    print(f"Downloading law XML from {URL}...")
    r = requests.get(URL)
    z = zipfile.ZipFile(io.BytesIO(r.content))
    print("Extracting...")
    z.extractall(TEMP_DIR)
    return os.path.join(TEMP_DIR, "law-xml-main", "us", "md", "cities", "baltimore")

def strip_ns(tag):
    if '}' in tag:
        return tag.split('}', 1)[1]
    return tag

def get_text(elem):
    text = ""
    if elem.text:
        text += elem.text
    for child in elem:
        text += get_text(child)
        if child.tail:
            text += child.tail
    return text

def parse_element(elem, level=1):
    md = ""
    tag = strip_ns(elem.tag)

    # Extract common attributes
    num = elem.find("./{*}num")
    heading = elem.find("./{*}heading")
    text_elem = elem.find("./{*}text")

    num_str = get_text(num) if num is not None else ""
    heading_str = get_text(heading) if heading is not None else ""

    # Handle containers/sections/paras
    if tag in ['container', 'section', 'para']:
        prefix_elem = elem.find("./{*}prefix")
        prefix_str = get_text(prefix_elem) if prefix_elem is not None else ""

        # Determine header level
        # Article -> level 1, Subtitle -> level 2, Section -> level 3, Para -> level 4+
        # But we can just use the 'level' argument passed recursively.

        header_prefix = "#" * level

        title_parts = []
        if prefix_str: title_parts.append(prefix_str)
        if num_str: title_parts.append(num_str)
        if heading_str: title_parts.append(heading_str)

        if title_parts:
            # If it's a paragraph like "(a)", maybe don't make it a header unless it has a heading?
            # Usually legal code structure:
            # Article I - General Provisions (H1)
            #   Section 1 - Corporate entity (H2)
            #     (a) ... (List item or H3)

            # Let's use a heuristic:
            # if 'Article' in prefix -> level 1
            # if 'Subtitle' in prefix -> level 2
            # if '§' in prefix -> level 3
            # else -> level 4 (bold) or list item

            if "Article" in prefix_str:
                current_level = 1
            elif "Subtitle" in prefix_str:
                current_level = 2
            elif "§" in prefix_str or tag == 'section':
                current_level = 3
            else:
                current_level = 4

            title = " ".join(title_parts)
            if current_level <= 3:
                md += f"{'#' * current_level} {title}\n\n"
            else:
                md += f"**{title}**\n\n"

    # Handle text content
    if text_elem is not None:
        content = get_text(text_elem)
        md += f"{content}\n\n"

    # Recurse for children
    for child in elem:
        child_tag = strip_ns(child.tag)
        if child_tag in ['container', 'section', 'para']:
            md += parse_element(child, level + 1)

    return md

def convert_xml_file(xml_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        # Find the main container or root
        # The root is often <document> or <container>
        # We start parsing from root
        return parse_element(root)
    except Exception as e:
        print(f"Error parsing {xml_path}: {e}")
        return ""

def fetch_and_convert_law():
    base_dir = download_and_extract_law()

    # Charter
    charter_file = os.path.join(base_dir, "charter.xml")
    if os.path.exists(charter_file):
        print("Converting Charter...")
        md_content = convert_xml_file(charter_file)
        with open(CHARTER_PATH, "w") as f:
            f.write(md_content)
        print(f"Saved Charter to {CHARTER_PATH}")
    else:
        print("Charter file not found!")

    # Code
    code_dir = os.path.join(base_dir, "code")
    if os.path.exists(code_dir):
        print("Converting Code...")
        xml_files = [f for f in os.listdir(code_dir) if f.endswith(".xml")]
        # Sort numerically if possible (1.xml, 2.xml, 10.xml)
        def sort_key(f):
            try:
                return int(os.path.splitext(f)[0])
            except ValueError:
                return 1000 # Put non-numeric at end

        xml_files.sort(key=sort_key)

        full_code_md = ""
        for xml_file in xml_files:
            print(f"Processing Code Article {xml_file}...")
            path = os.path.join(code_dir, xml_file)
            full_code_md += convert_xml_file(path)
            full_code_md += "\n---\n\n"

        with open(CODE_PATH, "w") as f:
            f.write(full_code_md)
        print(f"Saved Code to {CODE_PATH}")
    else:
        print("Code directory not found!")

    # Cleanup
    import shutil
    shutil.rmtree(TEMP_DIR)
    print("Cleanup complete.")

if __name__ == "__main__":
    fetch_and_convert_law()
