#!/usr/bin/env python3
import itertools
import argparse
import os.path
import json


argparser = argparse.ArgumentParser(
    description='Link bin outputs based on package.json contents')
argparser.add_argument(
    'bin_out', type=str,
    help='bin output path')
argparser.add_argument(
    'lib_out', type=str,
    help='lib output path')


def get_bin_attr_files(package_json):
    try:
        bins = package_json['bin']
    except KeyError:
        return tuple()
    else:
        # Python 3: JSON yields str
        if isinstance(bins, str):
            return ((package_json['name'], bins),)
        else:
            return tuple(bins.items())


def get_directories_bin_attr_files(package_json, lib_out):
    try:
        bins_dir = package_json['directories']['bin']
    except Exception:
        return tuple()
    else:
        dir_path = os.path.join(lib_out, bins_dir)
        if not os.path.isdir(dir_path):
            return tuple()
        return tuple((f, os.path.join(bins_dir, f)) for f in os.listdir(dir_path))


def resolve_bin_outputs(bin_out, lib_out, entries):
    for e in entries:
        yield (
            os.path.join(bin_out, e[0]),
            os.path.join(lib_out, e[1])
        )


if __name__ == '__main__':
    args = argparser.parse_args()

    with open(os.path.join(args.lib_out, 'package.json')) as f:
        package_json = json.load(f)

    for fout, fin in resolve_bin_outputs(
            args.bin_out, args.lib_out, itertools.chain(
                get_bin_attr_files(package_json),
                get_directories_bin_attr_files(package_json, args.lib_out))):

        os.symlink(fin, fout)
        os.chmod(fout, 0o755)

        # Print input file to stdout so we can pipe it to patchShebangs
        print(fin)
