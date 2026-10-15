#!/usr/bin/env bash
if [ $# -lt 1 ]; then
    echo "usage: $0 <scenario>   e.g. $0 fd04_p2_override" >&2
    exit 1
fi

s=$1
fst=out/$s/$s.fst
gtkw=waves/$s.gtkw

[ -f "$fst" ]  || { echo "no waveform: $fst (run: make $s)" >&2; exit 1; }
[ -f "$gtkw" ] || { echo "no save file: $gtkw" >&2; exit 1; }

gtkwave "$fst" "$gtkw"
