"""Values in Desk's ca65 includes (nes/include/*.inc), following their .include lines."""
import re
from pathlib import Path


def source(inc):
    """inc's text, then that of the files it .includes from beside it"""
    text = Path(inc).read_text()
    near = (Path(inc).parent / f for f in re.findall(r'^\s*\.include\s+"([^"]+)"', text, re.M))
    return text + "".join(source(p) for p in near if p.exists())


def symbols(inc):
    """{name: value} of the `name = $hex` or `name = decimal` lines"""
    out = {}
    for m in re.finditer(r"^(\w+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)\b", source(inc), re.M):
        out.setdefault(m[1], int(m[2][1:], 16) if m[2].startswith("$") else int(m[2]))
    return out


def define(inc, name):
    """a `.define name a, b, ...` list of $hex values"""
    return [int(v.strip().lstrip("$"), 16) for v in re.search(rf"\.define {name} (.*)", source(inc))[1].split(",")]
