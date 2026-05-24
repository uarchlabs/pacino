---
hide:
  - navigation
  - toc
title: ""
---

<style>
.md-typeset h1, .md-content__button { display: none; }
</style>

<style>
.pacino-landing *, .pacino-landing *::before, .pacino-landing *::after { box-sizing: border-box; margin: 0; padding: 0; }

.pacino-landing {
  --bg:            #21272e;
  --bg-deep:       #1c2128;
  --surface:       #2a3038;
  --surface-alt:   #232930;
  --border:        #353f4a;
  --accent:        #b84c25;
  --accent-bright: #d96b3f;
  --text:          #e8ecf0;
  --muted:         #8a97a6;
  --mono:          monospace;
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  display: flex;
  flex-direction: column;
  margin: 0 calc(-1 * var(--md-content-margin, 1rem));
  padding: 0;
}

/* ── NAV ── */
.pacino-landing .p-nav {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 32px;
  background: var(--bg-deep);
  border-bottom: 0.5px solid var(--border);
}

.pacino-landing .nav-left {
  display: flex;
  align-items: center;
  font-family: var(--mono);
  font-size: 13px;
}

.pacino-landing .nav-org {
  color: var(--muted);
  text-decoration: none;
  transition: color 0.15s;
}

.pacino-landing .nav-org:hover { color: var(--text); }

.pacino-landing .nav-sep {
  color: var(--border);
  margin: 0 8px;
}

.pacino-landing .nav-project { color: var(--accent-bright); }

.pacino-landing .nav-links {
  display: flex;
  align-items: center;
  gap: 24px;
}

.pacino-landing .nav-links a {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--muted);
  text-decoration: none;
  letter-spacing: 0.06em;
  transition: color 0.15s;
}

.pacino-landing .nav-links a:hover { color: var(--text); }

.pacino-landing .nav-gh {
  border: 0.5px solid var(--border) !important;
  border-radius: 3px;
  padding: 5px 12px;
}

.pacino-landing .nav-gh:hover {
  border-color: var(--accent) !important;
  color: var(--accent-bright) !important;
}

/* ── BANNER ── */
.pacino-landing .banner-wrap {
  width: 100%;
  border-bottom: 0.5px solid var(--border);
  overflow: hidden;
}

.pacino-landing .banner-wrap svg {
  display: block;
  width: 100%;
  height: auto;
}

/* ── MAIN ── */
.pacino-landing .p-main {
  flex: 1;
  max-width: 860px;
  width: 100%;
  margin: 0 auto;
  padding: 40px 32px 60px;
}

/* ── SECTION LABEL ── */
.pacino-landing .section-label {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--accent);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  margin-bottom: 18px;
  display: flex;
  align-items: center;
  gap: 10px;
}

.pacino-landing .section-label::after {
  content: '';
  flex: 1;
  height: 0.5px;
  background: var(--border);
}

/* ── OVERVIEW ── */
.pacino-landing .overview { margin-bottom: 40px; }

.pacino-landing .overview-quote {
  font-family: var(--mono);
  font-size: 12px;
  color: var(--accent-bright);
  margin-bottom: 14px;
  opacity: 0.7;
}

.pacino-landing .overview-text {
  font-size: 14px;
  color: var(--muted);
  line-height: 1.7;
  max-width: 680px;
}

.pacino-landing .overview-text strong {
  color: var(--text);
  font-weight: 500;
}

/* ── SPECS GRID ── */
.pacino-landing .specs-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 10px;
  margin-bottom: 40px;
}

.pacino-landing .spec-card {
  background: var(--surface);
  border: 0.5px solid var(--border);
  border-radius: 6px;
  padding: 14px 16px;
}

.pacino-landing .spec-label {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--accent);
  letter-spacing: 0.12em;
  text-transform: uppercase;
  margin-bottom: 6px;
}

.pacino-landing .spec-value {
  font-family: var(--mono);
  font-size: 13px;
  color: var(--text);
}

/* ── ARCH GRID ── */
.pacino-landing .arch-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-bottom: 40px;
}

.pacino-landing .arch-card {
  background: var(--surface-alt);
  border: 0.5px solid var(--border);
  border-radius: 6px;
  padding: 14px 16px;
}

.pacino-landing .arch-name {
  font-family: var(--mono);
  font-size: 12px;
  color: var(--text);
  margin-bottom: 5px;
  display: flex;
  align-items: center;
  gap: 8px;
}

.pacino-landing .arch-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--accent);
  flex-shrink: 0;
}

.pacino-landing .arch-detail {
  font-size: 12px;
  color: var(--muted);
  line-height: 1.5;
  padding-left: 13px;
}

/* ── METHODOLOGY ── */
.pacino-landing .method-block {
  background: var(--surface-alt);
  border: 0.5px solid var(--border);
  border-left: 2px solid var(--accent);
  border-radius: 0 6px 6px 0;
  padding: 16px 20px;
  margin-bottom: 40px;
}

.pacino-landing .method-block p {
  font-size: 13px;
  color: var(--muted);
  line-height: 1.7;
}

.pacino-landing .method-block p + p { margin-top: 10px; }

.pacino-landing .method-block strong {
  color: var(--text);
  font-weight: 500;
}

/* ── CTA ── */
.pacino-landing .cta-row {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.pacino-landing .cta {
  font-family: var(--mono);
  font-size: 12px;
  text-decoration: none;
  border-radius: 4px;
  padding: 9px 18px;
  transition: all 0.15s;
}

.pacino-landing .cta-primary {
  background: var(--accent);
  color: var(--text);
  border: 0.5px solid var(--accent);
}

.pacino-landing .cta-primary:hover {
  background: var(--accent-bright);
  border-color: var(--accent-bright);
}

.pacino-landing .cta-secondary {
  background: transparent;
  color: var(--muted);
  border: 0.5px solid var(--border);
}

.pacino-landing .cta-secondary:hover {
  border-color: var(--muted);
  color: var(--text);
}

/* ── FOOTER ── */
.pacino-landing .p-footer {
  border-top: 0.5px solid var(--border);
  padding: 14px 32px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: var(--bg-deep);
}

.pacino-landing .footer-text {
  font-family: var(--mono);
  font-size: 10px;
  color: #404a55;
}

.pacino-landing .footer-link {
  font-family: var(--mono);
  font-size: 10px;
  color: #404a55;
  text-decoration: none;
  transition: color 0.15s;
}

.pacino-landing .footer-link:hover { color: var(--muted); }

/* ── RESPONSIVE ── */
@media (max-width: 600px) {
  .pacino-landing .p-nav { padding: 12px 16px; }
  .pacino-landing .p-main { padding: 28px 16px 48px; }
  .pacino-landing .arch-grid { grid-template-columns: 1fr; }
  .pacino-landing .specs-grid { grid-template-columns: 1fr 1fr; }
  .pacino-landing .p-footer { padding: 12px 16px; flex-direction: column; gap: 6px; }
}
</style>

<div class="pacino-landing">

  <!-- NAV -->
  <!-- div class="p-nav">
    <div class="nav-left">
      <a class="nav-org" href="https://uarchlabs.com">uarchlabs</a>
      <span class="nav-sep">/</span>
      <span class="nav-project">pacino</span>
    </div>
    <div class="nav-links">
      <a href="#specs">specs</a>
      <a href="#architecture">arch</a>
      <a href="#methodology">methodology</a>
      <a href="https://github.com/uarchlabs/pacino" target="_blank" rel="noopener" class="nav-gh">github ↗</a>
    </div>
  </div -->

  <!-- BANNER -->
  <div class="banner-wrap">
    <svg width="1200" height="400" viewBox="0 0 1200 400" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
          <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#353f4a" stroke-width="0.5"/>
        </pattern>
        <pattern id="traces" width="120" height="120" patternUnits="userSpaceOnUse">
          <path d="M20 0 L20 40 L60 40 L60 80 L100 80 L100 120" fill="none" stroke="#353f4a" stroke-width="0.8"/>
          <path d="M80 0 L80 20 L40 20 L40 60 L0 60" fill="none" stroke="#353f4a" stroke-width="0.8"/>
        </pattern>
      </defs>
      <rect width="1200" height="400" fill="#21272e"/>
      <rect width="1200" height="400" fill="url(#grid)" opacity="0.6"/>
      <rect width="1200" height="400" fill="url(#traces)" opacity="0.5"/>
      <ellipse cx="900" cy="200" rx="380" ry="260" fill="#b84c25" opacity="0.06"/>
      <rect x="80" y="60" width="2" height="280" fill="#b84c25" opacity="0.8" rx="1"/>
      <g transform="translate(112, 148)">
        <rect width="64" height="64" rx="12" fill="#353f4a"/>
        <rect width="64" height="64" rx="12" fill="none" stroke="#b84c25" stroke-width="1" opacity="0.5"/>
        <path d="M14 18 L14 36 Q14 50 22 50 L42 50 Q50 50 50 36 L50 18" stroke="#d96b3f" stroke-width="3.5" stroke-linecap="round" fill="none"/>
        <line x1="8" y1="18" x2="56" y2="18" stroke="#8a97a6" stroke-width="2" stroke-linecap="round"/>
        <circle cx="32" cy="42" r="4" fill="#b84c25"/>
      </g>
<!--
      <text x="196" y="186" font-family="-apple-system,sans-serif" font-size="56" font-weight="700" letter-spacing="-2" fill="#e8ecf0">u</text>
      <text x="228" y="186" font-family="-apple-system,sans-serif" font-size="56" font-weight="700" letter-spacing="-2" fill="#d96b3f">arch</text>
      <text x="376" y="186" font-family="-apple-system,sans-serif" font-size="56" font-weight="700" letter-spacing="-2" fill="#e8ecf0">labs</text>
      <text x="196" y="218" font-family="-apple-system,sans-serif" font-size="15" font-weight="500" letter-spacing="0.5" fill="#d96b3f">PACINO</text>
      <text x="262" y="218" font-family="-apple-system,sans-serif" font-size="15" font-weight="400" letter-spacing="0.5" fill="#8a97a6"> · Open Source 8-issue OOO RISC-V Processor</text>
-->
      <!-- text x="196" y="186" font-family="-apple-system,sans-serif" font-size="56" font-weight="700" letter-spacing="-2" fill="#e8ecf0">u</text -->
      <text x="228" y="186" font-family="-apple-system,sans-serif" font-size="56" font-weight="700" letter-spacing="-2" fill="#d96b3f">Pacino</text>
      <text x="435" y="186" font-family="-apple-system,sans-serif" font-size="56" font-weight="700" letter-spacing="-2" fill="#e8ecf0">Docs</text>
      <!-- text x="196" y="218" font-family="-apple-system,sans-serif" font-size="15" font-weight="500" letter-spacing="0.5" fill="#d96b3f">PACINO</text -->
      <text x="196" y="218" font-family="-apple-system,sans-serif" font-size="15" font-weight="400" letter-spacing="0.5" fill="#8a97a6"> · Open Source 8-issue OOO RISC-V Processor</text>

      <line x1="196" y1="238" x2="580" y2="238" stroke="#353f4a" stroke-width="1"/>
      <!-- g transform="translate(196, 260)">
        <circle cx="6" cy="6" r="3" fill="#b84c25"/>
        <text x="18" y="10" font-family="-apple-system,sans-serif" font-size="13" font-weight="500" fill="#e8ecf0">Open RTL</text>
        <text x="18" y="28" font-family="-apple-system,sans-serif" font-size="12" fill="#8a97a6">Synthesizable, forkable, yours</text>
      </g -->
      <!-- g transform="translate(196, 308)">
        <circle cx="6" cy="6" r="3" fill="#b84c25"/>
        <text x="18" y="10" font-family="-apple-system,sans-serif" font-size="13" font-weight="500" fill="#e8ecf0">AI co-design methods</text>
        <text x="18" y="28" font-family="-apple-system,sans-serif" font-size="12" fill="#8a97a6">Prompts, loops, and rationale — documented</text>
      </g -->

      <g transform="translate(740, 80)" opacity="0.85">
        <rect x="0" y="0" width="360" height="240" rx="6" fill="none" stroke="#353f4a" stroke-width="1.5"/>
        <rect x="100" y="60" width="160" height="120" rx="4" fill="#353f4a" stroke="#b84c25" stroke-width="1"/>
        <text x="180" y="116" font-family="monospace" font-size="11" fill="#d96b3f" text-anchor="middle" font-weight="500">CORE</text>
        <text x="180" y="132" font-family="monospace" font-size="9" fill="#8a97a6" text-anchor="middle">AI co-designed</text>
        <rect x="14" y="14" width="70" height="40" rx="3" fill="#353f4a" stroke="#8a97a6" stroke-width="0.5"/>
        <text x="49" y="37" font-family="monospace" font-size="9" fill="#8a97a6" text-anchor="middle">I-CACHE</text>
        <rect x="276" y="14" width="70" height="40" rx="3" fill="#353f4a" stroke="#8a97a6" stroke-width="0.5"/>
        <text x="311" y="37" font-family="monospace" font-size="9" fill="#8a97a6" text-anchor="middle">D-CACHE</text>
        <rect x="110" y="194" width="140" height="36" rx="3" fill="#353f4a" stroke="#8a97a6" stroke-width="0.5"/>
        <text x="180" y="215" font-family="monospace" font-size="9" fill="#8a97a6" text-anchor="middle">MEM CTRL</text>
        <rect x="14" y="80" width="50" height="80" rx="3" fill="#353f4a" stroke="#8a97a6" stroke-width="0.5"/>
        <text x="39" y="120" font-family="monospace" font-size="8" fill="#8a97a6" text-anchor="middle">I/O</text>
        <rect x="296" y="80" width="50" height="80" rx="3" fill="#353f4a" stroke="#8a97a6" stroke-width="0.5"/>
        <text x="321" y="120" font-family="monospace" font-size="8" fill="#8a97a6" text-anchor="middle">I/O</text>
        <line x1="84" y1="34" x2="100" y2="90" stroke="#353f4a" stroke-width="1" stroke-dasharray="3,2"/>
        <line x1="276" y1="34" x2="260" y2="90" stroke="#353f4a" stroke-width="1" stroke-dasharray="3,2"/>
        <line x1="64" y1="120" x2="100" y2="120" stroke="#353f4a" stroke-width="1" stroke-dasharray="3,2"/>
        <line x1="296" y1="120" x2="260" y2="120" stroke="#353f4a" stroke-width="1" stroke-dasharray="3,2"/>
        <line x1="180" y1="180" x2="180" y2="194" stroke="#b84c25" stroke-width="1" stroke-dasharray="3,2" opacity="0.7"/>
        <line x1="14" y1="186" x2="346" y2="186" stroke="#353f4a" stroke-width="1"/>
        <circle cx="110" cy="186" r="2.5" fill="#8a97a6" opacity="0.6"/>
        <circle cx="250" cy="186" r="2.5" fill="#8a97a6" opacity="0.6"/>
        <line x1="30" y1="0" x2="30" y2="-8" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="60" y1="0" x2="60" y2="-8" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="90" y1="0" x2="90" y2="-8" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="270" y1="0" x2="270" y2="-8" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="300" y1="0" x2="300" y2="-8" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="330" y1="0" x2="330" y2="-8" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="30" y1="240" x2="30" y2="248" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="60" y1="240" x2="60" y2="248" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="300" y1="240" x2="300" y2="248" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="330" y1="240" x2="330" y2="248" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="0" y1="100" x2="-8" y2="100" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="0" y1="140" x2="-8" y2="140" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="360" y1="100" x2="368" y2="100" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
        <line x1="360" y1="140" x2="368" y2="140" stroke="#8a97a6" stroke-width="1" opacity="0.5"/>
      </g>
      <rect x="0" y="380" width="1200" height="20" fill="#353f4a"/>
      <text x="80" y="394" font-family="monospace" font-size="10" fill="#8a97a6">uarchlabs.github.io/pacino</text>
      <text x="1120" y="394" font-family="monospace" font-size="10" fill="#8a97a6" text-anchor="end">open source · 2026</text>
    </svg>
  </div>

  <!-- MAIN -->
  <div class="p-main">

    <!-- OVERVIEW -->
    <section class="overview">
      <div class="section-label">// overview</div>
      <div class="overview-quote">"I'm out of order? You're out of order!"</div>
      <p class="overview-text">
        Pacino is an open source 8-issue out-of-order RISC-V processor targeting the RVA23S64 profile. RTL is written in SystemVerilog, simulated with Verilator, and verified with a combination of directed tests, functional coverage, formal analysis via SymbiYosys and riscv-formal, and spike-dasm as an independent oracle. Gate synthesis targets Yosys with FPGA mapping via Quartus and Vivado. Design decisions, AI-assisted co-design records, and architectural rationale are committed alongside the RTL.
      </p>
    </section>

    <!-- SPECS -->
    <section id="specs">
      <div class="section-label">// specs</div>
      <div class="specs-grid">
        <div class="spec-card"><div class="spec-label">architecture</div><div class="spec-value">RISC-V RVA23S64</div></div>
        <div class="spec-card"><div class="spec-label">issue width</div><div class="spec-value">8-issue OOO</div></div>
        <div class="spec-card"><div class="spec-label">rtl language</div><div class="spec-value">SystemVerilog</div></div>
        <div class="spec-card"><div class="spec-label">simulator</div><div class="spec-value">Verilator 5.x</div></div>
        <div class="spec-card"><div class="spec-label">compiler</div><div class="spec-value">GCC 16.x, LLVM 22.x RISC-V</div></div>
        <div class="spec-card"><div class="spec-label">status</div><div class="spec-value" style="color:#d96b3f;">active</div></div>
      </div>
    </section>

    <!-- ARCHITECTURE -->
    <section id="architecture">
      <div class="section-label">// architecture</div>
      <iframe
        src="microarchitecture.html"
        title="Pacino microarchitecture block diagram"
        style="width:100%; height:520px; border:0.5px solid #353f4a; border-radius:6px; display:block;"
        loading="lazy"
      ></iframe>
    </section>

<!--
    <section id="architecture">
      <div class="section-label">// architecture</div>
      <div class="arch-grid">
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>frontend</div><div class="arch-detail">icache · ftq · ifu · ibuf · decode · bpu</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>dispatch</div><div class="arch-detail">rename · prf (i/f/v/mm) · rob · reservation stations</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>execute</div><div class="arch-detail">int · float · vector · matrix · atomics</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>lsu</div><div class="arch-detail">agu · lq · sq · fwd · l1d · vlsu · mmlsu</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>memory</div><div class="arch-detail">l2 · l3 · prefetch</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>mmu</div><div class="arch-detail">itlb · dtlb · l2tlb · ptw</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>uncore</div><div class="arch-detail">tilelink · csr · pmu · trace</div></div>
        <div class="arch-card"><div class="arch-name"><span class="arch-dot"></span>protection</div><div class="arch-detail">pma · pmp</div></div>
      </div>
    </section>
-->
    <!-- METHODOLOGY -->
    <section id="methodology">
      <div class="section-label">// ai co-design methodology</div>
      <div class="method-block">
        <p>Pacino is designed using a structured AI co-design methodology — a domain expert directing a dual-agent workflow across architectural planning and RTL implementation. Prompts, iteration history, and design rationale are committed alongside the RTL as first-class artifacts. Full methodology documentation is in the <a href="https://uarchlabs.com/faq.html" style="color:#d96b3f;text-decoration:none;">FAQ</a> and the repo.</p>
      </div>
    </section>

    <!-- CTA -->
    <section>
      <div class="section-label">// get started</div>
      <div class="cta-row">
        <a class="cta cta-primary" href="https://github.com/uarchlabs/pacino" target="_blank" rel="noopener">view on github ↗</a>
        <a class="cta cta-secondary" href="overview/">read the docs ↗</a>
        <a class="cta cta-secondary" href="https://uarchlabs.com/faq.html" target="_blank" rel="noopener">read the FAQ</a>
        <a class="cta cta-secondary" href="https://uarchlabs.com">← uarchlabs</a>
      </div>
    </section>

  </div>

  <!-- FOOTER -->
  <div class="p-footer">
    <span class="footer-text">pacino · uarchlabs · open source hardware &middot; &copy; 2026</span>
    <a class="footer-link" href="https://github.com/uarchlabs/pacino" target="_blank" rel="noopener">github.com/uarchlabs/pacino ↗</a>
  </div>

</div>

