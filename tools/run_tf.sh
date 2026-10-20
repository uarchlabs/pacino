#! /usr/bin/env bash

tools/ticfinder/tools/ticfinder.py \
  --model en_core_web_md \
  --html reports \
  --waiver-dir waivers \
  blogs/BLOG_bpu_20_cluster_simulation.md

#  --gen-waivers disabled \
#  --gen-waivers enabled \
#  --no-waivers \
