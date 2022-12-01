#!/usr/bin/env python3

# Copyright (c) 2022, Cedric Velandres
# SPDX-License-Identifier: MIT

"""
Generate root kconfig that links all specified kconfig files
"""

KCONFIG_ROOT_HEADER="# AUTOGENERATED FILE. DO NOT MODIFY "
KCONFIG_DEFAULT_MAINMENU="Kconfig Project Configuration"

import argparse
from io import TextIOWrapper
import logging
import re
import os
import shutil
from tkinter import commondialog

class KconfigMerge:
    def __init__(self, title: str, kconfig_root: str, overwrite = 'always') -> None:
        self.title = title
        self.kconfig_root = kconfig_root
        self.sources = []
        self.parent_dir = os.path.dirname(kconfig_root)
        self.common_dir = ""
        self.overwrite = overwrite
        self.kconfig_sources = []
        self.logger = logging.getLogger("KconfigMerge")
        self.headers = ["# AUTOGENERATED FILE. DO NOT MODIFY"]

        # precreate parent dir
        os.makedirs(self.parent_dir, exist_ok=True)
        pass

    def _get_source_relpath(self, source_path: str) -> str:
        """
        Returns the relative source path of input path with respect to common path of all sources
        """
        return os.path.relpath(source_path, self.common_dir)

    def _get_parent_relpath(self, source_path: str) -> str:
        """
        Returns the relative source path of input path with respect to parent path of output kconfig root
        Also creates directories for the path
        """
        parent_relpath = os.path.join(self.parent_dir, self._get_source_relpath(source_path))
        os.makedirs(os.path.dirname(parent_relpath), exist_ok=True)
        return parent_relpath

    def _parse_kconfig(self, kconfig_source: str) -> list:
        kconfig_source_relpath = self._get_source_relpath(kconfig_source)
        kconfig_parent_relpath = self._get_parent_relpath(kconfig_source)
        kconfig_source_dirname = os.path.dirname(kconfig_source)

        # store parsed kconfig sources and destination kconfig file
        self.kconfig_sources.append({kconfig_source, kconfig_parent_relpath})

        self.logger.debug("Parsing %s", kconfig_source_relpath)
        with open(kconfig_source, 'r') as f_source, open(kconfig_parent_relpath, 'w') as f_source_out:
            for f_source_line in f_source:
                match = re.match(r"^source\s*\"([^\"]*)\"", f_source_line)
                if match and match.group(1):
                    source_abspath = os.path.join(kconfig_source_dirname, match.group(1))
                    # recurse call _parse_kconfig
                    source_relpath = self._parse_kconfig(source_abspath)
                    f_source_out.write("source \"%s\"\n" % source_relpath)
                    continue
                else:
                    f_source_out.write(f_source_line)

        return kconfig_source_relpath

    def import_sources(self, sources: list):
        """
        Imports a set of kconfig files to generate a tree of kconfig with adjusted
        source paths wre to the common dir of all kconfig paths
        """
        self.common_dir = os.path.commonpath(sources)
        with open(self.kconfig_root, 'w') as kconfig_root:
            # write headers
            for header in self.headers:
                kconfig_root.write("%s\n" % header)

            kconfig_root.write("mainmenu \"%s Configuration\"\n" % self.title)

            for source in sources:
                # parse kconfig file to search for nested sources
                # and update source paths to parent dir
                relpath = self._parse_kconfig(source)
                kconfig_root.write("source \"%s\"\n" % relpath)
                pass
        pass

    def summary(self):
        self.logger.info("Imported %d kconfig sources" % len(self.kconfig_sources))
        self.logger.info("Generator Kconfig at %s" % self.kconfig_root)

def main():
    parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter, description=__doc__)

    parser.add_argument("-s", "--silent", action='store_true', help="suppress all log output")
    parser.add_argument("--kconfig", required=True, help="path for output file for project Kconfig")
    parser.add_argument("--title", required=True, help="Project Title")
    parser.add_argument("--sources", nargs='+', help="Paths to kconfig for projects")

    args = parser.parse_args()

    if not args.silent:
        logging.basicConfig()

    # convert all sources to absolute and check if it exists
    kconfig_sources = []
    for source in args.sources:
        if not os.path.isabs(source):
            source = os.path.abspath(source)

        if not os.path.exists(source):
            raise Exception("Could not find file: %s" % source)
        elif not os.path.isfile(source):
            raise Exception("Not a file: %s" % source)
        kconfig_sources.append(source)

    kconfig = KconfigMerge(args.title, args.kconfig)
    kconfig.import_sources(kconfig_sources)
    kconfig.summary()

if __name__ == "__main__":
    main()

