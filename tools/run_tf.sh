#! /usr/bin/env bash

tools/ticfinder/tools/ticfinder.py \
  --model en_core_web_md \
  --html reports \
  --waiver-dir waivers \
  --gen-waivers enabled \
  blogs/BLOG_bpu_18_before_the_cluster.md

#  --no-waivers \
