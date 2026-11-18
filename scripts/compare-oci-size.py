#!/usr/bin/env python3
"""Compare compressed registry layer bytes in two Buildx OCI tar exports.

Usage: python3 scripts/compare-oci-size.py BASELINE.oci.tar CANDIDATE.oci.tar
Does not extract archives or require Docker, jq, or third-party packages.
"""

import argparse
import json
import tarfile


def image_sizes(path):
    """Return unique layer sizes for each runnable platform."""
    with tarfile.open(path, "r:*") as archive:
        def read_json(name):
            with archive.extractfile(name) as stream:
                return json.load(stream)

        def read_blob(digest):
            algorithm, value = digest.split(":", 1)
            return read_json(f"blobs/{algorithm}/{value}")

        result = {}

        def walk(descriptor):
            annotations = descriptor.get("annotations", {})
            if annotations.get("vnd.docker.reference.type") == "attestation-manifest":
                return
            data = read_blob(descriptor["digest"])
            if "manifests" in data:
                for child in data["manifests"]:
                    walk(child)
                return
            if "layers" not in data or "config" not in data:
                return
            config = read_blob(data["config"]["digest"])
            platform = descriptor.get("platform") or config
            os = platform.get("os")
            arch = platform.get("architecture")
            if not os or not arch or os == "unknown" or arch == "unknown":
                return
            key = "/".join(filter(None, (os, arch, platform.get("variant"))))
            if key in result:
                raise ValueError(f"{path}: multiple runnable manifests for {key}")
            result[key] = {layer["digest"]: layer["size"] for layer in data["layers"]}

        for descriptor in read_json("index.json")["manifests"]:
            walk(descriptor)
        if not result:
            raise ValueError(f"{path}: no runnable image manifests")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    args = parser.parse_args()
    baseline = image_sizes(args.baseline)
    candidate = image_sizes(args.candidate)
    if baseline.keys() != candidate.keys():
        parser.error(f"platform mismatch: {sorted(baseline)} vs {sorted(candidate)}")
    print("platform\tbaseline_bytes\tcandidate_bytes\tdelta_bytes\tdelta_percent\tnew_layer_bytes")
    for platform in sorted(baseline):
        old = baseline[platform]
        new = candidate[platform]
        old_size = sum(old.values())
        new_size = sum(new.values())
        delta = new_size - old_size
        percent = f"{100 * delta / old_size:+.2f}%" if old_size else "n/a"
        new_bytes = sum(size for digest, size in new.items() if digest not in old)
        print(f"{platform}\t{old_size}\t{new_size}\t{delta:+d}\t{percent}\t{new_bytes}")


if __name__ == "__main__":
    main()
