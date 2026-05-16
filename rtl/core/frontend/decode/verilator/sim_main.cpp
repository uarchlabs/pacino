// sim_main.cpp - Verilator wrapper for instr_decoder testbench
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
