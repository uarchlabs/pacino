#! /usr/bin/env bash

tools/ticfinder/tools/ticfinder.py \
  --model en_core_web_md \
  --html reports \
  --waiver-dir waivers \
  blogs/BLOG_bpu_21_loop_predictor.md

#  --gen-waivers enabled \
#  --no-waivers \
