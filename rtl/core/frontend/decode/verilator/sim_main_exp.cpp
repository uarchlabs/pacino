// sim_main_exp.cpp - Verilator wrapper for rvc_expander testbench
// Compatible with Verilator 5.020 with --timing
// Testbench module is named 'tb' (Verilator class: Vtb)

#include "Vtb.h"
#include "verilated.h"
#include <iostream>

int main(int argc, char** argv) {
    VerilatedContext* const contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    Vtb* const top = new Vtb{contextp};

    // Advance time and eval until testbench calls $finish.
    // Each timeInc(1) corresponds to one time unit (#1) in the testbench,
    // allowing combinational logic to re-settle between test steps.
    while (!contextp->gotFinish()) {
        contextp->timeInc(1);
        top->eval();
    }

    top->final();

    std::cout << "Simulation complete." << std::endl;

    delete top;
    delete contextp;
    return 0;
}
