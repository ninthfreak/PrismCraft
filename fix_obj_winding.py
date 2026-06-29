#!/usr/bin/env python3
"""Fix face winding order in OBJ files exported by PrismCraft.

Reverses vertex order on all face lines so back-face culling works
correctly in Godot. Includes a --check mode to detect the problem
without modifying files.

Usage:
    python fix_obj_winding.py file.obj [file2.obj ...]
    python fix_obj_winding.py --check file.obj [file2.obj ...]
"""

import sys
import os
import re


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


def length(a):
    return (a[0] ** 2 + a[1] ** 2 + a[2] ** 2) ** 0.5


def parse_face_token(token):
    """Parse a face token, returning (vertex_index, normal_index or None).

    Handles formats: 'v', 'v/vt', 'v/vt/vn', 'v//vn'
    """
    parts = token.split("/")
    vi = int(parts[0])
    ni = None
    if len(parts) == 3 and parts[2]:
        ni = int(parts[2])
    elif len(parts) == 2 and token.count("/") == 2:
        # v//vn format
        ni = int(parts[1]) if parts[1] else None
    return vi, ni


def parse_obj(path):
    """Parse vertices, normals, and faces from an OBJ file."""
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
            elif parts[0] == "f" and len(parts) >= 4:
                tokens = parts[1:]
                vis = []
                ni = None
                for t in tokens:
                    vi, n = parse_face_token(t)
                    vis.append(vi)
                    if n is not None:
                        ni = n
                faces.append((vis, ni))

    return vertices, normals, faces


def check_obj_file(path):
    """Check if an OBJ file has inverted winding.

    For faces with explicit normals: compares cross-product winding
    against the declared normal.

    For faces without normals: computes the winding normal and checks
    if it points inward (away from the face centroid relative to the
    model center).

    Returns (total_faces, bad_faces).
    """
    vertices, normals, faces = parse_obj(path)

    if not faces or not vertices:
        return 0, 0

    total = 0
    bad = 0

    # Compute model center for heuristic check on faces without normals
    cx = sum(v[0] for v in vertices) / len(vertices)
    cy = sum(v[1] for v in vertices) / len(vertices)
    cz = sum(v[2] for v in vertices) / len(vertices)
    center = (cx, cy, cz)

    for vi_list, ni in faces:
        if len(vi_list) < 3:
            continue

        v0 = vertices[vi_list[0] - 1]
        v1 = vertices[vi_list[1] - 1]
        v2 = vertices[vi_list[2] - 1]

        edge1 = sub(v1, v0)
        edge2 = sub(v2, v0)
        winding_normal = cross(edge1, edge2)

        if length(winding_normal) < 1e-10:
            continue

        total += 1

        if ni is not None and ni >= 1 and ni <= len(normals):
            declared = normals[ni - 1]
            d = dot(winding_normal, declared)
            if d > 0:
                bad += 1
        else:
            # Heuristic: face normal should point away from model center
            face_center = (
                (v0[0] + v1[0] + v2[0]) / 3.0,
                (v0[1] + v1[1] + v2[1]) / 3.0,
                (v0[2] + v1[2] + v2[2]) / 3.0,
            )
            outward = sub(face_center, center)
            d = dot(winding_normal, outward)
            if d > 0:
                bad += 1

    return total, bad


def fix_face_line(line):
    """Reverse vertex order in a face line."""
    parts = line.split()
    if parts[0] != "f":
        return line
    vertices = parts[1:]
    vertices.reverse()
    return "f " + " ".join(vertices) + "\n"


def fix_obj_file(path):
    """Fix winding order by reversing all face vertex orders in-place."""
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
            elif total == 0:
                print(f"SKIP {path}: no faces found")
            else:
                print(f"OK   {path}: {total} faces, winding correct")
        else:
            count = fix_obj_file(path)
            print(f"Fixed {count} faces in {path}")

    if check_mode:
        sys.exit(1 if any_bad else 0)


if __name__ == "__main__":
    main()
