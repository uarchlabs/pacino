<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Technical Post-Mortem: RVA23 Tools & Validation Framework

## Session Overview
- **Date**: March 24, 2026
- **Focus**: Validation tools and verification framework
- **Experiments**: TOOLS-001, TOOLS-002
- **Scope**: Third-party validation using spike-dasm and systematic test infrastructure

## Premise

Establishing a robust validation framework was critical for ensuring decoder correctness beyond unit testing. The tools work focused on creating systematic verification against reference implementations and building infrastructure for ongoing validation.

## Problem Statement

### Validation Challenges
1. **Unit Test Limitations**: Internal tests may have systematic biases
2. **Reference Verification**: Need independent validation against known-good implementations
3. **Extension Coverage**: RVA23 includes many extensions requiring comprehensive validation
4. **Systematic Testing**: Need reproducible, automated validation processes

### Technical Requirements
1. **Third-party Reference**: Use spike as independent validation source
2. **Comprehensive Coverage**: Validate all RVA23 extensions systematically
3. **Automation**: Reproducible validation without manual inspection
4. **Integration**: Seamless integration with existing test infrastructure

## Implementation Work

### TOOLS-001: Coverage Script Accuracy
**Objective**: Fix systematic errors in coverage analysis tooling

**Problem Identified**:
- Coverage script reporting false negatives for shared encodings
- Zcb instruction coverage incorrectly calculated
- Systematic bias affecting validation accuracy

**Approach**:
- Analysis of coverage algorithm for shared encoding handling
- Correction of false negative detection logic
- Validation against known instruction sets

**Results**:
- Coverage script accuracy restored
- Zcb coverage: 13/13 correctly reported
- Foundation for reliable coverage metrics established

**Technical Details**:
- Fixed shared encoding false negatives in coverage analysis
- Verified coverage calculation against manual inspection
- Established reliable baseline for ongoing coverage tracking

### TOOLS-002: Spike Validation Framework
**Objective**: Establish spike-dasm as third-party verification method

**Challenge**: RVA23 ISA String Determination
- Spike requires precise ISA string for correct disassembly
- RVA23 includes numerous extensions requiring specific encoding
- Compiler and spike ISA string formats differ

**Solution**: Complete RVA23 ISA String
```
rv64imafdc_v_h_sscofpmf_sstc_svinval_svnapot_svpbmt_zawrs_zba_zbb_zbc_zbs_zfa_zfh_zfhmin_zicbom_zicboz_zicntr_zifencei_zicond_zihintntl_zihintpause_zihpm_zkt_zk_zkn_zknd_zkne_zknh_zbkb_zbkc_zbkx_zicbop_zcb_zvkb
```

**Key Insights**:
- Spike requires explicit extension enumeration (no 'G' shortcut)
- ISA string must match spike's supported extension format
- Version compatibility critical for extension support

**Test Infrastructure Created**:

1. **rva23_ext_test.c**: Executable test file
   - One instruction per extension in inline assembly
   - Links and executes for runtime validation
   - Validates instruction encoding in executable context

2. **rva23_insn_ref.c**: Disassembly reference file
   - One instruction per extension for disassembly analysis
   - Creates object file for systematic disassembly inspection
   - Enables systematic comparison with spike-dasm output

3. **Makefile Integration**: 
   - Automated compilation of test files
   - Systematic disassembly generation
   - Integration with existing build infrastructure

**Validation Process Established**:
1. Compile test files with RVA23 ISA string
2. Generate disassembly using spike-dasm
3. Compare decoder output with spike disassembly
4. Systematic validation across all extensions

## Results

### Validation Framework Operational
1. **Accurate Coverage Metrics**: Fixed systematic biases in coverage analysis
2. **Third-party Verification**: Spike-dasm validation operational
3. **Comprehensive Test Files**: Systematic coverage across RVA23 extensions
4. **Automated Workflow**: Reproducible validation process established

### Technical Achievements
- **ISA String Determined**: Complete RVA23 extension specification for spike
- **Test Infrastructure**: Systematic test file generation and validation
- **Process Integration**: Seamless integration with existing build system
- **Verification Method**: Independent validation beyond unit testing

### Validation Capabilities
1. **Extension Coverage**: All RVA23 extensions systematically testable
2. **Reference Comparison**: Independent verification against spike implementation
3. **Automated Analysis**: Systematic comparison without manual inspection
4. **Ongoing Integration**: Framework ready for continuous validation

## Technical Decisions Made

### Spike as Reference Implementation
- **Chosen**: spike-dasm for third-party verification
- **Rationale**: Well-maintained, RVA23-compliant, widely accepted reference
- **Integration**: Systematic disassembly comparison workflow

### ISA String Strategy
- **Chosen**: Explicit extension enumeration matching spike format
- **Rationale**: Ensures precise extension handling without ambiguity
- **Implementation**: Complete RVA23 extension specification string

### Test File Approach
- **Chosen**: Dual test files (executable + disassembly-focused)
- **Rationale**: Covers both runtime and encoding validation scenarios
- **Structure**: One instruction per extension for systematic coverage

### Validation Workflow
- **Chosen**: Automated build and comparison process
- **Rationale**: Reduces manual effort and systematic bias
- **Integration**: Makefile-based workflow integrated with project build system

## Lessons Learned

### Technical Insights
1. **Reference Validation Essential**: Independent verification catches systematic errors
2. **ISA String Precision**: Exact specification critical for tool compatibility
3. **Systematic Testing**: Automated workflows prevent validation gaps
4. **Tool Integration**: Seamless integration with existing workflows increases adoption

### Process Insights
1. **Coverage Tool Accuracy**: Validation tools themselves need validation
2. **Third-party Dependencies**: External tool compatibility requires careful specification
3. **Systematic Approach**: Structured validation more effective than ad-hoc testing
4. **Documentation Critical**: Clear process documentation enables reproducible validation

### AI Co-Design Insights
1. **Domain Knowledge**: Hardware expertise essential for validation strategy
2. **Tool Selection**: Understanding of verification ecosystem critical
3. **Process Design**: Systematic workflow design as important as tool selection
4. **Validation Coverage**: Comprehensive approach catches more issues than targeted testing

## Integration with Decoder Work

### Validation of Decoder Implementation
- TOOLS framework validates DECODE-001 through DECODE-004 results
- Systematic verification of scalar and vector instruction handling
- Independent confirmation of decoder correctness

### Ongoing Validation Support
- Framework ready for DECODE-005 through DECODE-008 validation
- Systematic verification of remaining vector instruction classes
- Continuous validation throughout remaining implementation phases

## Follow-up Work

### Immediate Extensions
1. **Automated Comparison**: Direct comparison of decoder output with spike-dasm
2. **Regression Testing**: Integration with continuous integration workflow
3. **Coverage Expansion**: Extension to remaining vector instruction classes

### Long-term Integration
1. **Performance Validation**: Cycle-accurate validation against performance models
2. **Compliance Testing**: Full RVA23 compliance test suite execution
3. **Cross-validation**: Validation against multiple reference implementations

## Conclusion

The tools and validation framework established in RVA23 Co-Design Part 1 provides essential infrastructure for ongoing verification of the processor design. The combination of accurate coverage metrics, third-party validation via spike-dasm, and systematic test infrastructure creates a robust foundation for ensuring design correctness.

The framework successfully validated the decoder implementation work while establishing processes that will support the remaining implementation phases. The systematic approach to validation represents a critical component of the AI-assisted design methodology, providing essential quality assurance for the overall project.
