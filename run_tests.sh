#!/bin/bash
# Complete test runner script for VGA card project

set -e  # Exit on any error

echo "=========================================="
echo "VGA Card Project Test Suite"
echo "=========================================="

# Check for required tools
command -v iverilog >/dev/null 2>&1 || { echo "Error: iverilog not found. Install Icarus Verilog." >&2; exit 1; }

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

run_test() {
    local test_name="$1"
    local make_target="$2"
    
    log_info "Running $test_name..."
    
    if make "$make_target" > "${test_name}.log" 2>&1; then
        log_success "$test_name completed successfully"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$test_name failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        echo "  See ${test_name}.log for details"
    fi
}

# Phase 1: Syntax Check
log_info "Phase 1: Syntax Check"
echo "----------------------------------------"

if make syntax_check > syntax_check.log 2>&1; then
    log_success "Syntax check passed"
else
    log_error "Syntax check failed - see syntax_check.log"
    exit 1
fi

echo

# Phase 2: Individual Module Tests
log_info "Phase 2: Individual Module Tests"
echo "----------------------------------------"

run_test "VGA Timing Test" "run_vga_timing"
run_test "CPU Interface Test" "run_cpu_interface"

echo

# Phase 3: Mode-Specific Tests
log_info "Phase 3: Mode-Specific Tests"
echo "----------------------------------------"

# Check if font file exists
if [ ! -f "font_8x16.mem" ]; then
    log_warning "font_8x16.mem not found - text mode test may fail"
fi

run_test "Text Mode Test" "run_text_mode"
run_test "Graphics Mode Test" "run_graphics_mode"

echo

# Phase 4: Integration Test
log_info "Phase 4: Integration Test"
echo "----------------------------------------"

run_test "Integration Test" "run_integration"

echo

# Phase 5: Resource Analysis (if Gowin EDA available)
log_info "Phase 5: Resource Analysis"
echo "----------------------------------------"

if command -v gw_sh >/dev/null 2>&1; then
    log_info "Running synthesis check with Gowin EDA..."
    if gw_sh synthesis_check.tcl > synthesis.log 2>&1; then
        log_success "Synthesis check completed"
        
        # Extract resource utilization info
        if [ -f "utilization_report.txt" ]; then
            log_info "Resource Utilization Summary:"
            echo "----------------------------------------"
            grep -E "(LUT|FF|BRAM|DSP)" utilization_report.txt | head -10
            echo "----------------------------------------"
        fi
    else
        log_warning "Synthesis check failed - see synthesis.log"
    fi
else
    log_warning "Gowin EDA not found - skipping synthesis check"
    log_info "Install Gowin EDA to verify Tang Nano-20k compatibility"
fi

echo

# Test Summary
log_info "Test Summary"
echo "=========================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    log_success "All tests passed! ✅"
    echo ""
    log_info "Your VGA card design is ready for Tang Nano-20k implementation"
    echo ""
    echo "Next steps:"
    echo "1. Review any synthesis warnings in synthesis.log"
    echo "2. Prepare level shifter hardware for 5V ↔ 3.3V conversion"
    echo "3. Plan VGA DAC circuit with voltage dividers"
    echo "4. Test on actual Tang Nano-20k hardware"
    
    exit 0
else
    log_error "Some tests failed ❌"
    echo ""
    echo "Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
    echo "Please review the log files for details and fix the issues before proceeding."
    
    exit 1
fi