import argparse
from pathlib import Path
from intelhex import IntelHex

parser = argparse.ArgumentParser()
parser.add_argument("application", type=Path)
parser.add_argument("release", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()

application = IntelHex(str(args.application))
assert application.segments() == [(0x26000, 0x2600E), (0x26010, 0x26020)]
combined = IntelHex(str(args.release))
# Only data addresses are relevant when checking an image against a partition.
application.start_addr = None
combined.start_addr = None
combined.merge(application, overlap="error")
combined.write_hex_file(str(args.output))
assert IntelHex(str(args.output)).segments() == combined.segments()
print("Application segments:", [(hex(start), hex(end)) for start, end in application.segments()])
print("Merged segments:", [(hex(start), hex(end)) for start, end in combined.segments()])
