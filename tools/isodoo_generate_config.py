#!/usr/bin/env python3
# Copyright  Alexandre Díaz <dev@redneboa.es>
import os
import configparser
import argparse
from pathlib import Path
from collections import defaultdict

parser = argparse.ArgumentParser(
    description="Collects OCONF_ environment variables and saves them to an .conf file"
)
parser.add_argument("output", help="Path to the output .conf file")
args = parser.parse_args()

config = configparser.ConfigParser()

if os.path.exists(args.output):
    config.read(args.output)
    if not config.has_section("options"):
        config.add_section("options")
else:
    config.add_section("options")

to_write = defaultdict(dict)
for key, value in os.environ.items():
    if key.startswith(("OCONF__", "FOCONF__")):
        if key.startswith("FOCONF__") and os.path.isfile(value):
            value = Path(value).read_text().strip()
        _, config_section, config_key = key.split("__", 2)
        to_write[config_section][config_key] = value

for config_section, config_values in to_write.items():
    if not config.has_section(config_section):
        config.add_section(config_section)
    for config_key in sorted(to_write[config_section].keys()):
        config.set(config_section, config_key, to_write[config_section][config_key])

with open(args.output, "w", encoding="utf-8") as configfile:
    config.write(configfile)
