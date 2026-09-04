  Audit — misc/ras_theory_of_operation.md verified against ras.sv,
  tb_ras.sv, and the RAS planning docs. The technical core held up;
  four defects, all in documentation.

  Corrected — ras_decisions.md (§3.2, §3.3, §6.1), ras_interfaces.md
  (§3, §4, IC-RAS-06, §9.2), bp_structs_pkg.sv RETURN enum comment,
  and the theory-of-operation doc itself.

  Added — TD#121 for the commit-stack full/empty encoding, and a
  Session-069 entry in PROJECT_STATUS.md with the run counts.

  Verified — 62 targets across bpu and ftq, forced with -B, all green,
  every recorded count reconfirmed.

  Two open threads if you want them later: the bp_cluster.sv Module
  Status row still shows BP-097's 973 while 1795 lives in the
  session-067 notes, and the seven SVG links in the
  theory-of-operation doc only resolve once that file moves to blogs/.

