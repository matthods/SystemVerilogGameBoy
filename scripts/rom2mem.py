#!/usr/bin/env python3
import argparse
import sys
import os

def rom_to_mem(input_file, output_file, word_size, reverse_endian):
    """
    Converts a binary file into a text format containing hexadecimal strings,
    suitable for Verilog $readmemh or FPGA memory initialization file (.mem).
    """
    if not os.path.exists(input_file):
        print(f"Error: Input file '{input_file}' not found.", file=sys.stderr)
        sys.exit(1)

    try:
        with open(input_file, 'rb') as f:
            bindata = f.read()
    except Exception as e:
        print(f"Error reading input file: {e}", file=sys.stderr)
        sys.exit(1)

    # Pad data with zeros if it doesn't align with the word size
    remainder = len(bindata) % word_size
    if remainder != 0:
        padding_size = word_size - remainder
        bindata += b'\x00' * padding_size
        print(f"Warning: Input file size not a multiple of {word_size} bytes. Padded with {padding_size} bytes.")

    try:
        with open(output_file, 'w') as out_f:
            for i in range(0, len(bindata), word_size):
                word_bytes = bindata[i:i+word_size]
                
                # If required, reverse endianness within the word
                if reverse_endian:
                    word_bytes = word_bytes[::-1]
                
                # Convert bytes to a single hex string matching the word size width
                hex_str = ''.join(f'{b:02x}' for b in word_bytes)
                out_f.write(f"{hex_str}\n")
                
        print(f"Successfully converted '{input_file}' to '{output_file}' ({len(bindata) // word_size} words written).")
    except Exception as e:
        print(f"Error writing output file: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description="Convert a binary ROM file into a text hexadecimal file (.mem) for Verilog/HDL memory initialization."
    )
    parser.add_argument("-i", "--input", required=True, help="Path to the input binary (.bin/.out) file")
    parser.add_argument("-o", "--output", required=True, help="Path to the output memory text (.mem/.txt) file")
    parser.add_argument("-w", "--word-size", type=int, default=4, choices=[1, 2, 4, 8],
                        help="Word size in bytes: 1 (8-bit), 2 (16-bit), 4 (32-bit), 8 (64-bit). Default is 4.")
    parser.add_argument("-r", "--reverse", action="store_true",
                        help="Reverse the byte order (endianness) within each word.")

    args = parser.parse_args()
    rom_to_mem(args.input, args.output, args.word_size, args.reverse)

if __name__ == "__main__":
    main()
