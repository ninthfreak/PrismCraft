#!/usr/bin/env python3
"""Fix face winding order in OBJ files exported by PrismCraft.

Reverses vertex order on all face lines so back-face culling works
correctly in Godot. Safe to run on already-fixed files (running twice
restores the original, so only run once).

Usage:
    python fix_obj_winding.py file.obj [file2.obj ...]
    python fix_obj_winding.py --check file.obj [file2.obj ...]
"""

import sys
import os
import re


def parse_vertex(token):
    """Extract vertex index from an OBJ face token like '5//3'."""
    return int(token.split("/")[0])


def parse_obj(path):
    """Parse vertices and faces from an OBJ file."""
    vertices = []
    normals = []
    faces = []

    with open(path, "r") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v" and len(parts) >= 4:
                vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
            elif parts[0] == "vn" and len(parts) >= 4:
                normals.append((float(parts[1]), float(parts[2]), float(parts[3])))
            elif parts[0] == "f":
                tokens = parts[1:]
                vi = [parse_vertex(t) for t in tokens]
                ni = None
                match = re.match(r"\d+//(\d+)", tokens[0])
                if match:
                    ni = int(match.group(1))
                faces.append((vi, ni))

    return vertices, normals, faces


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def check_obj_file(path):
    """Check if an OBJ file has inverted winding.

    Returns (total_faces, bad_faces) where bad_faces is the count of
    faces whose vertex winding produces a normal opposite to the
    declared face normal.
    """
    vertices, normals, faces = parse_obj(path)

    if not faces or not normals:
        return 0, 0

    total = 0
    bad = 0

    for vi_list, ni in faces:
        if ni is None or ni < 1 or ni > len(normals):
            continue
        if len(vi_list) < 3:
            continue

        v0 = vertices[vi_list[0] - 1]
        v1 = vertices[vi_list[1] - 1]
        v2 = vertices[vi_list[2] - 1]

        edge1 = sub(v1, v0)
        edge2 = sub(v2, v0)
        winding_normal = cross(edge1, edge2)

        declared = normals[ni - 1]
        d = dot(winding_normal, declared)

        total += 1
        if d > 0:
            bad += 1

    return total, bad


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
        print("Usage: python fix_obj_winding.py [--check] file.obj [file2.obj ...]")
        print("  --check  Report winding issues without modifying files")
        sys.exit(1)

    check_mode = sys.argv[1] == "--check"
    files = sys.argv[2:] if check_mode else sys.argv[1:]

    if not files:
        print("No files specified.")
        sys.exit(1)

    any_bad = False
    for path in files:
        if not os.path.isfile(path):
            print(f"Skipping {path}: not found")
            continue

        if check_mode:
            total, bad = check_obj_file(path)
            if bad > 0:
                print(f"BAD  {path}: {bad}/{total} faces have inverted winding")
                any_bad = True
            else:
                print(f"OK   {path}: {total} faces, winding correct")
        else:
            count = fix_obj_file(path)
            print(f"Fixed {count} faces in {path}")

    if check_mode:
        sys.exit(1 if any_bad else 0)


if __name__ == "__main__":
    main()
