#!/usr/bin/env python3
"""Fix face winding order in OBJ files exported by PrismCraft.

Reverses vertex order on all face lines so back-face culling works
correctly in Godot. Safe to run on already-fixed files (running twice
restores the original, so only run once).

Usage:
    python fix_obj_winding.py file.obj [file2.obj ...]
    python fix_obj_winding.py *.obj
"""

import sys
import os


def fix_face_line(line):
    parts = line.split()
    if parts[0] != "f":
        return line
    vertices = parts[1:]
    vertices.reverse()
    return "f " + " ".join(vertices) + "\n"


def fix_obj_file(path):
    with open(path, "r") as f:
        lines = f.readlines()

    fixed = 0
    output = []
    for line in lines:
        if line.startswith("f "):
            output.append(fix_face_line(line))
            fixed += 1
        else:
            output.append(line)

    with open(path, "w") as f:
        f.writelines(output)

    return fixed


def main():
    if len(sys.argv) < 2:
        print("Usage: python fix_obj_winding.py file.obj [file2.obj ...]")
        sys.exit(1)

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print(f"Skipping {path}: not found")
            continue
        count = fix_obj_file(path)
        print(f"Fixed {count} faces in {path}")


if __name__ == "__main__":
    main()
