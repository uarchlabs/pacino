# sram_init and FAST_INIT Behavior
```
 FILE:    planning/arch/sram_init.md
 SOURCE:  session-043
 STATUS:  DRAFT
 UPDATED: 2026-05-19
 CONTACT: Jeff Nye
```

This covers the purpose, behavior and usage of the SRAM 
initialization module, sram_init.

---

## Operation

sram_init.sv is a shared initializer module. There are two
modes, normal and FAST_INIT. FAST_INIT is triggered by a
command line plusargs.

### Terms

The module instantiating sram_init is called the parent module.
The module containing the RAM to be initialized is called the
table module. The parent module may also be the table module
in some designs.

### Normal mode

In normal mode sram_init runs a state machine that asserts an
address, write data and RAM control signals for each entry
in the RAM.

The address begins at zero, and increments up to the maximum
number of entries. 

sram_init cycles detect the rising edge of reset which triggers
the sram_init state machine. 

The state machine has a delayed start feature, where it will
not begin the ram initialization sequence for the number of
clocks defined by module parameter START_DELAY. If START_DELAY
is zero the FSM begins ram initialization immediately.

While active the sram_init module will assert it's active output.

When all entries have been initialized the sram_init module will
assert ready.

It is the responsibility of the parent module to tie the sram_init
ready signal to the parent modules ready output.

It is the responsibility of the parent module to tie the sram_init
outputs to the table modules. 

The most efficient design uses a single sram_init module for multiple
table modules. It is the responsibility of the parent module to
create this organization and distribute the sram_init RAM control
signals to the proper pins of the table module(s)


### FAST_INIT mode

In FAST_INIT mode RAM initialization is not done by the sram_init
module, it is done by an initial statement found in the table
modules. 

sram_init.sv has no FAST_INIT awareness. It always runs the
full state machine: PENDING -> INIT -> DONE. active and ready
follow the state machine unconditionally.

It is the responsbility of the parent module to gate off or make 
otherwise ineffective all control signals from sram_init.

Further it is the responsibility of the parent module to assert
it ready output immediately in FAST_INIT mode.

### Sample table module initial statement

An example of a table module FAST_INIT initial statement is
shown:
```
  initial begin
    int fast_init;
    fast_init = 0;
    void'($value$plusargs("TAGE_FAST_INIT=%d", fast_init));
    if (fast_init != 0) begin
      for (int b = 0; b < 2; b++) begin
        for (int i = 0; i < RAM_ENTRIES; i++) begin
          u_ram_s0.mem[b][i] =
            ALLOC_DATA_WIDTH'(TAGE_SRAM_INIT_VALUE);
          u_ram_s1.mem[b][i] =
            ALLOC_DATA_WIDTH'(TAGE_SRAM_INIT_VALUE);
        end
      end
    end
  end
```

This is an example, TAGE_FAST_INIT is specific to the TAGE design.
Each branch predictor typically has a separate fast init plus arg.

TAGE_SRAM_INIT_VALUE is a parameter specific to a TAGE table module.
Each table module will have a similar parameter.

The RAM_ENTRIES is specific to the RAM used in the table module.

### Sample parent module initial statement
The parent module sets a signal indicating FAST_INIT mode.
This example is taken from tage.sv

```
  logic fast_init_r;
  initial begin
    int fi;
    fi = 0;
    void'($value$plusargs("TAGE_FAST_INIT=%d", fi));
    fast_init_r = (fi != 0) ? 1'b1 : 1'b0;
  end
```

### Sample parent module tie offs.

tage.sv reads the +TAGE_FAST_INIT plusarg in an initial block
and sets fast_init_r. It then muxes all tbl_ri_* outputs:

  assign tbl_ri_active = fast_init_r ? 1'b0 : ri_active_raw;
  assign tbl_ri_wr     = fast_init_r ? 1'b0 : ri_wr_raw;
  assign tbl_ri_wa     = fast_init_r ? '0   : ri_wa_raw;
  assign tbl_ri_wd     = fast_init_r ? '0   : ri_wd_raw;
  assign tage_rdy      = fast_init_r ? 1'b1 : ri_rdy_raw;

The tbl_* signals are routed to the table modules as needed.

This suppresses sram_init outputs at the top level. sram_init
still runs its full internal state machine; its outputs are
ignored. 

---

## Module Inventory: sram_init Consumers

Confirmed consumers 

  tage.sv          -- TAGE top (parent module)
  tage_table.sv    -- a TAGE table module 
  tage_bim.sv      -- a TAGE table module, this is specialized
                      table module but shares same sram_init in tage
  ittage.sv        -- ITTAGE top (parent module) 
  ittage_table.sv  -- ITTAGE table module


Future consumers requiring same treatment at implementation:

  sc.sv            -- SC top (parent module)
  sc_table.sv      -- SC table module
  ubtb.sv          -- uBTB, design is TBD.

Modules confirmed NOT to instantiate sram_init:

  loop_pred.sv     -- No SRAM. Pure registered counter array.

---

## Plusarg Names by Module

  tage_table.sv:    +TAGE_FAST_INIT=1
  tage.sv:          +TAGE_FAST_INIT=1   (same as table)
  ittage_table.sv:  +ITTAGE_FAST_INIT=1 
  ittage.sv:        +ITTAGE_FAST_INIT=1 (same as table)
  sc.sv:            +TAGE_FAST_INIT=1   uses TAGE fast init
  sc_table.sv:      +TAGE_FAST_INIT=1   (same as table)

Note: sram_init.sv has no need to read a plusarg. 

