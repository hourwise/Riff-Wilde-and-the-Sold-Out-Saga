#!/usr/bin/env python3
"""Strip the mesh and textures out of animation-only glTF files.

    python tools/strip_animation_glb.py <source-dir> <output-dir>

Meshy exports one .glb per animation, and each one carries a full copy of the
character: the mesh, the skin, and a 4K texture set. Twenty animations is
twenty duplicates of a model we already have, which is how a nineteen-animation
export arrives at 569 MB. Only the animation tracks are wanted.

WHAT MUST SURVIVE THE STRIP
---------------------------
The `skins` array. This is not optional and it is not obvious.

Godot decides whether a glTF rig becomes a Skeleton3D by looking for a skin. No
skin means the bones import as an ordinary Node3D chain, and every animation
track then addresses a path like `Armature/Hips/Spine02/...` while the character
it is merged onto has `Armature/Skeleton3D:Hips`. Nothing errors. The clips are
present, `has_animation` says yes, playback reports success, and the character
stands in its bind pose for the entire game.

That is exactly what happened to Riff: 551 MB came down to 1.1 MB, all 49 tests
passed, and he could not move. The skin costs a few hundred bytes.
"""

import json
import os
import struct
import sys

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(path):
    with open(path, "rb") as handle:
        data = handle.read()

    gltf, binary, offset = None, b"", 12
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + length]
        if kind == JSON_CHUNK:
            gltf = json.loads(chunk)
        elif kind == BIN_CHUNK:
            binary = chunk
        offset += 8 + length
    return gltf, binary


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    body = struct.pack("<II", len(text), JSON_CHUNK) + text

    if binary:
        binary += b"\x00" * (-len(binary) % 4)
        body += struct.pack("<II", len(binary), BIN_CHUNK) + binary

    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def strip(gltf, binary):
    """Keeps animations, the node hierarchy and the skin. Drops everything else."""
    keep = set()

    for animation in gltf.get("animations", []):
        for sampler in animation["samplers"]:
            keep.add(sampler["input"])
            keep.add(sampler["output"])

    # The inverse bind matrices belong to the skin, and the skin is the whole
    # point of this exercise. See the module docstring.
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            keep.add(skin["inverseBindMatrices"])

    accessors, views, buffer = [], [], bytearray()
    remap = {}

    for index in sorted(keep):
        accessor = dict(gltf["accessors"][index])

        if "bufferView" in accessor:
            view = gltf["bufferViews"][accessor["bufferView"]]
            start = view.get("byteOffset", 0)
            chunk = binary[start:start + view["byteLength"]]

            # Four-byte alignment, because accessor component types up to
            # 4 bytes wide are read straight out of the buffer.
            buffer += b"\x00" * (-len(buffer) % 4)
            views.append({
                "buffer": 0,
                "byteOffset": len(buffer),
                "byteLength": len(chunk),
            })
            buffer += chunk
            accessor["bufferView"] = len(views) - 1

        remap[index] = len(accessors)
        accessors.append(accessor)

    for animation in gltf.get("animations", []):
        for sampler in animation["samplers"]:
            sampler["input"] = remap[sampler["input"]]
            sampler["output"] = remap[sampler["output"]]

    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = remap[skin["inverseBindMatrices"]]

    for node in gltf.get("nodes", []):
        node.pop("mesh", None)

    gltf["accessors"] = accessors
    gltf["bufferViews"] = views
    gltf["buffers"] = [{"byteLength": len(buffer)}] if buffer else []
    for section in ("meshes", "materials", "textures", "images", "samplers"):
        gltf.pop(section, None)

    return gltf, bytes(buffer)


def clip_name(filename):
    """Meshy wraps the clip name in a long prefix and a _withSkin suffix."""
    name = os.path.splitext(os.path.basename(filename))[0]
    marker = "_Animation_"
    if marker in name:
        name = name.split(marker, 1)[1]
    return name.removesuffix("_withSkin")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1

    source, output = sys.argv[1], sys.argv[2]
    os.makedirs(output, exist_ok=True)

    before = after = 0
    for filename in sorted(os.listdir(source)):
        if not filename.endswith(".glb") or "_Animation_" not in filename:
            continue

        path = os.path.join(source, filename)
        gltf, binary = read_glb(path)
        gltf, binary = strip(gltf, binary)

        if not gltf.get("skins"):
            print("  REFUSED %s: no skin to keep" % filename)
            continue

        destination = os.path.join(output, clip_name(filename) + ".glb")
        write_glb(destination, gltf, binary)

        before += os.path.getsize(path)
        after += os.path.getsize(destination)
        print("  %-36s %7.1f MB -> %6.1f KB" % (
            clip_name(filename), os.path.getsize(path) / 1e6,
            os.path.getsize(destination) / 1e3))

    print("\n  total %.0f MB -> %.1f MB" % (before / 1e6, after / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
