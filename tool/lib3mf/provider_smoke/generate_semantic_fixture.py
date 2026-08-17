#!/usr/bin/env python3
"""Generate a deterministic clean-room 3MF semantic fixture for BrepSight tests."""

from __future__ import annotations

import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>
"""

RELATIONSHIPS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""

MODEL = """<?xml version="1.0" encoding="UTF-8"?>
<model unit="centimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
  <resources>
    <object id="1" type="model" name="Tetra" partnumber="MESH-001">
      <mesh>
        <vertices>
          <vertex x="0" y="0" z="0"/>
          <vertex x="1" y="0" z="0"/>
          <vertex x="0" y="1" z="0"/>
          <vertex x="0" y="0" z="1"/>
        </vertices>
        <triangles>
          <triangle v1="0" v2="2" v3="1"/>
          <triangle v1="0" v2="1" v3="3"/>
          <triangle v1="0" v2="3" v3="2"/>
          <triangle v1="1" v2="2" v3="3"/>
        </triangles>
      </mesh>
    </object>
    <object id="2" type="model" name="Pair" partnumber="ASM-PAIR">
      <components>
        <component objectid="1"/>
        <component objectid="1" transform="1 0 0 0 1 0 0 0 1 2 0 0"/>
      </components>
    </object>
    <object id="3" type="model" name="Nested" partnumber="ASM-NESTED">
      <components>
        <component objectid="2" transform="1 0 0 0 1 0 0 0 1 0 3 0"/>
      </components>
    </object>
  </resources>
  <build>
    <item objectid="3" partnumber="BUILD-NESTED" transform="1 0 0 0 1 0 0 0 1 1 0 0"/>
    <item objectid="1" partnumber="BUILD-MESH" transform="-1 0 0 0 1 0 0 0 1 8 0 0"/>
  </build>
</model>
"""


def write_member(archive: ZipFile, name: str, text: str) -> None:
    info = ZipInfo(name)
    info.date_time = (1980, 1, 1, 0, 0, 0)
    info.compress_type = ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(info, text.encode("utf-8"))


def main() -> int:
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "brepsight-semantic.3mf")
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w") as archive:
        write_member(archive, "[Content_Types].xml", CONTENT_TYPES)
        write_member(archive, "_rels/.rels", RELATIONSHIPS)
        write_member(archive, "3D/3dmodel.model", MODEL)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
