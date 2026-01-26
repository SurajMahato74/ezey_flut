
import sys

def count_braces(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            open_braces = content.count('{')
            close_braces = content.count('}')
            print(f"File: {filepath}")
            print(f"Open braces: {open_braces}")
            print(f"Close braces: {close_braces}")
            if open_braces != close_braces:
                print("MISMATCH!")
            else:
                print("Balanced.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        count_braces(sys.argv[1])
    else:
        print("Usage: python count_braces.py <filepath>")
