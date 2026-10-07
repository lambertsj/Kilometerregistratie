#!/usr/bin/env python3
"""Registreert een nieuw Swift-bestand in project.pbxproj.

Gebruik: add_to_xcodeproj.py <pad-relatief-aan-groep> --like <bestaand-broerbestand.swift>
Het nieuwe bestand komt in dezelfde groep en target als het broerbestand.
Voorbeeld: add_to_xcodeproj.py Platform/TimeSource.swift --like TripRecorder.swift
"""
import argparse, re, sys, uuid

PBX = "Kilometerregistratie.xcodeproj/project.pbxproj"

def new_id(text):
    while True:
        candidate = uuid.uuid4().hex[:24].upper()
        if candidate not in text:
            return candidate

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--like", required=True)
    args = parser.parse_args()
    name = args.path.rsplit("/", 1)[-1]

    s = open(PBX).read()
    if f"/* {name} */" in s:
        sys.exit(f"{name} staat al in het project")

    ref = re.search(r"\t\t(\w{24}) /\* %s \*/ = \{isa = PBXFileReference" % re.escape(args.like), s)
    build = re.search(r"\t\t(\w{24}) /\* %s in Sources \*/ = \{isa = PBXBuildFile" % re.escape(args.like), s)
    if not ref or not build:
        sys.exit(f"{args.like} niet gevonden in het project")
    ref_id, build_id = ref.group(1), build.group(1)
    file_id = new_id(s)
    new_build_id = new_id(s + file_id)

    s = s.replace("/* End PBXBuildFile section */",
        f"\t\t{new_build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};\n/* End PBXBuildFile section */", 1)
    s = s.replace("/* End PBXFileReference section */",
        f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = {args.path}; sourceTree = \"<group>\"; }};\n/* End PBXFileReference section */", 1)
    group_line = re.search(r"(\t+)%s /\* %s \*/,\n" % (ref_id, re.escape(args.like)), s)
    s = s[:group_line.end()] + f"{group_line.group(1)}{file_id} /* {name} */,\n" + s[group_line.end():]
    src_line = re.search(r"(\t+)%s /\* %s in Sources \*/,\n" % (build_id, re.escape(args.like)), s)
    s = s[:src_line.end()] + f"{src_line.group(1)}{new_build_id} /* {name} in Sources */,\n" + s[src_line.end():]

    open(PBX, "w").write(s)
    print(f"{name} toegevoegd")

main()
