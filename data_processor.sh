#!/bin/bash

# A script to analyze, reformat, and summarize raw data files.
# This version is enhanced with header detection, data type analysis,
# and command-line options for more control.
#
# Usage: ./data_processor.sh <file> [-d <delimiter>] [-o <output_file>] [-s <skip_lines>] [-f <format>] [-h]
#
# Options:
#   -d <delimiter>    Specify the input file delimiter (e.g., ',').
#   -o <output_file>  Specify the output file path. The extension is determined by the format.
#   -s <skip_lines>   Number of lines to skip from the beginning of the file (e.g., header lines).
#   -f <format>       Output format: 'csv', 'json', or 'md' (Markdown). Default is csv.
#   -h                Display this help message.
#
# Ensure the script is made executable with: chmod +x data_processor.sh

# --- Configuration ---
# Number of lines to use for analysis and preview.
PREVIEW_LINES=10

# Default output directory.
OUTPUT_DIR="./structured_data"

# Create the output directory if it doesn't exist.
mkdir -p "$OUTPUT_DIR"

# --- Function Definitions ---

# Function to display usage information.
usage() {
    echo "Usage: $0 <file> [-d <delimiter>] [-o <output_file>] [-s <skip_lines>] [-f <format>] [-h]"
    echo ""
    echo "  <file>            Path to the raw data file."
    echo "  -d <delimiter>    Specify the input file delimiter (e.g., ',')."
    echo "  -o <output_file>  Specify the output file path. The extension is determined by the format."
    echo "  -s <skip_lines>   Number of lines to skip from the beginning of the file (e.g., header lines)."
    echo "  -f <format>       Output format: 'csv', 'json', or 'md' (Markdown). Default is csv."
    echo "  -h                Display this help message."
    echo ""
    exit 1
}

# Function to detect the most likely delimiter.
# It checks for common delimiters on a sample of lines.
detect_delimiter() {
    local file_path="$1"
    local sample_lines=$(head -n 100 "$file_path")
    local comma_count=$(echo "$sample_lines" | grep -o "," | wc -l)
    local tab_count=$(echo "$sample_lines" | grep -o $'\t' | wc -l)
    local space_count=$(echo "$sample_lines" | grep -o " " | wc -l)

    if [[ "$comma_count" -gt "$tab_count" && "$comma_count" -gt "$space_count" ]]; then
        echo ","
    elif [[ "$tab_count" -gt "$comma_count" ]]; then
        echo -e "\t"
    elif [[ "$space_count" -gt 0 ]]; then
        echo " "
    else
        echo ""
    fi
}

# Function to detect if a file has a header.
# A simple heuristic: check if the first line has a different character type (e.g., string)
# compared to the second line (e.g., numbers).
detect_header() {
    local file_path="$1"
    local first_line=$(head -n 1 "$file_path")
    local second_line=$(head -n 2 "$file_path" | tail -n 1)

    if [[ "$first_line" =~ [a-zA-Z] ]] && [[ ! "$second_line" =~ [a-zA-Z] ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# Function to analyze the data type of a single column.
analyze_column_type() {
    local file_path="$1"
    local col_index="$2"
    local sample_lines=$(head -n 100 "$file_path")
    local col_data=$(echo "$sample_lines" | cut -d',' -f"$col_index")

    local int_count=$(echo "$col_data" | grep -E '^[0-9]+$' | wc -l)
    local float_count=$(echo "$col_data" | grep -E '^[0-9]+\.[0-9]+$' | wc -l)
    local alpha_count=$(echo "$col_data" | grep -E '[a-zA-Z]' | wc -l)

    if [[ "$int_count" -ge 90 ]]; then
        echo "Integer"
    elif [[ "$float_count" -ge 90 ]]; then
        echo "Float"
    elif [[ "$alpha_count" -gt 0 ]]; then
        echo "String/Mixed"
    else
        echo "Unknown"
    fi
}

# Function to reformat data into a CSV. This is an intermediate step.
reformat_to_csv() {
    local file_path="$1"
    local delimiter="$2"
    local skip_lines="$3"
    local temp_csv_path="$4"

    if [[ -z "$delimiter" ]]; then
        echo "No delimiter detected. Cannot reformat." >&2
        return 1
    elif [[ "$delimiter" == $'\t' ]]; then
        tail -n +$((skip_lines + 1)) "$file_path" | tr '\t' ',' > "$temp_csv_path"
    else
        tail -n +$((skip_lines + 1)) "$file_path" | tr "$delimiter" ',' > "$temp_csv_path"
    fi
    return 0
}

# Function to convert CSV data to JSON format.
convert_to_json() {
    local csv_path="$1"
    local json_path="$2"

    # Use awk to convert CSV to JSON array of objects.
    # Reads the first line for headers and then processes the rest of the lines.
    awk '
    BEGIN {
        FS=",";
        printf "[";
        header_set = 0;
    }
    NR==1 {
        for (i=1; i<=NF; i++) {
            headers[i] = $i;
        }
        next;
    }
    {
        if (header_set) {
            printf ",";
        }
        printf "{";
        for (i=1; i<=NF; i++) {
            printf "\"%s\":\"%s\"%s", headers[i], $i, (i==NF ? "" : ",");
        }
        printf "}";
        header_set = 1;
    }
    END {
        printf "]\n";
    }' "$csv_path" > "$json_path"
}

# Function to convert CSV data to Markdown format.
convert_to_markdown() {
    local csv_path="$1"
    local md_path="$2"

    # Use awk to format as a Markdown table.
    # The first line becomes the header, and the second line becomes the separator.
    awk '
    BEGIN {
        FS=",";
        OFS="|";
    }
    NR==1 {
        # Print header row
        print "|" $0 "|";
        # Print separator row
        separator = "";
        for (i=1; i<=NF; i++) {
            separator = separator "-";
        }
        gsub(/[^\|]/, "-", $0);
        print "|" $0 "|";
        next;
    }
    {
        # Print data rows
        print "|" $0 "|";
    }' "$csv_path" > "$md_path"
}


# --- Main Script Logic ---

# Initialize variables with defaults.
INPUT_FILE=""
INPUT_DELIMITER=""
OUTPUT_FILE=""
LINES_TO_SKIP=0
OUTPUT_FORMAT="csv"

# Process command-line options using `getopts`.
while getopts ":d:o:s:f:h" opt; do
    case "$opt" in
        d) INPUT_DELIMITER="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        s) LINES_TO_SKIP="$OPTARG" ;;
        f) OUTPUT_FORMAT="$OPTARG" ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done
shift $((OPTIND-1))

INPUT_FILE="$1"

# Check if a filename argument was provided.
if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: No file specified."
    usage
fi

# Check if the file exists and is readable.
if [[ ! -f "$INPUT_FILE" || ! -r "$INPUT_FILE" ]]; then
    echo "Error: File not found or not readable: $INPUT_FILE"
    exit 1
fi

echo "--- Data Analysis Started ---"
echo "Input file: $INPUT_FILE"

# Detect delimiter if not specified by the user.
if [[ -z "$INPUT_DELIMITER" ]]; then
    echo "Attempting to detect delimiter..."
    INPUT_DELIMITER=$(detect_delimiter "$INPUT_FILE")
    if [[ -z "$INPUT_DELIMITER" ]]; then
        echo "Warning: Could not reliably detect a delimiter. Assuming space."
        INPUT_DELIMITER=" "
    fi
    DELIMITER_NAME="Detected: '$INPUT_DELIMITER'"
else
    DELIMITER_NAME="User-specified: '$INPUT_DELIMITER'"
fi

# Set output file path and extension.
if [[ -z "$OUTPUT_FILE" ]]; then
    FILE_BASE_NAME=$(basename -- "$INPUT_FILE")
    OUTPUT_FILE="${OUTPUT_DIR}/${FILE_BASE_NAME%.*}_structured.${OUTPUT_FORMAT}"
fi

# Create a temporary CSV file for processing.
TEMP_CSV_FILE=$(mktemp)
reformat_to_csv "$INPUT_FILE" "$INPUT_DELIMITER" "$LINES_TO_SKIP" "$TEMP_CSV_FILE"

if [[ $? -ne 0 ]]; then
    echo "Error during reformatting. Exiting."
    rm -f "$TEMP_CSV_FILE"
    exit 1
fi

# Get file and column counts from the new file.
LINE_COUNT=$(wc -l < "$TEMP_CSV_FILE")
# Use the first line to get the number of columns.
COLUMN_COUNT=$(head -n 1 "$TEMP_CSV_FILE" | grep -o ',' | wc -l)
COLUMN_COUNT=$((COLUMN_COUNT + 1))

# Detect header.
HAS_HEADER=$(detect_header "$TEMP_CSV_FILE")

echo ""
echo "--- Analysis Summary ---"
echo "Original File:   $INPUT_FILE"
echo "Output File:     $OUTPUT_FILE"
echo "Output Format:   $OUTPUT_FORMAT"
echo "Lines to Skip:   $LINES_TO_SKIP"
echo "Total Rows:      $LINE_COUNT"
echo "Delimiter:       $DELIMITER_NAME"
echo "Columns:         $COLUMN_COUNT"
echo "Header Detected: $HAS_HEADER"

echo ""
echo "--- Column Data Type Analysis ---"
# Loop through columns and analyze data type.
for (( i=1; i<=COLUMN_COUNT; i++ )); do
    COL_TYPE=$(analyze_column_type "$TEMP_CSV_FILE" "$i")
    echo "  Column $i: $COL_TYPE"
done

# Convert the temporary CSV file to the final output format.
case "$OUTPUT_FORMAT" in
    "csv")
        mv "$TEMP_CSV_FILE" "$OUTPUT_FILE"
        ;;
    "json")
        convert_to_json "$TEMP_CSV_FILE" "$OUTPUT_FILE"
        rm -f "$TEMP_CSV_FILE"
        ;;
    "md")
        convert_to_markdown "$TEMP_CSV_FILE" "$OUTPUT_FILE"
        rm -f "$TEMP_CSV_FILE"
        ;;
    *)
        echo "Error: Unsupported output format: $OUTPUT_FORMAT"
        rm -f "$TEMP_CSV_FILE"
        exit 1
        ;;
esac

echo ""
echo "--- Structured Data Preview (First $PREVIEW_LINES lines) ---"
if [[ -f "$OUTPUT_FILE" ]]; then
    head -n "$PREVIEW_LINES" "$OUTPUT_FILE"
else
    echo "Preview not available for this format."
fi

echo ""
echo "--- Structured Data Preview (Last $PREVIEW_LINES lines) ---"
if [[ -f "$OUTPUT_FILE" ]]; then
    tail -n "$PREVIEW_LINES" "$OUTPUT_FILE"
else
    echo "Preview not available for this format."
fi

echo ""
echo "--- Processing Complete ---"
echo "Your structured data is ready at: $OUTPUT_FILE"

