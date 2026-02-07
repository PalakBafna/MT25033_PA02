#!/bin/bash
# MT25033
# MT25033_Part_C_Experiment.sh
# Automated Experiment Script for PA02: Network I/O Analysis
# Roll Number: MT25033
#
# This script:
# 1. Compiles all implementations
# 2. Sets up network namespaces for isolated testing
# 3. Runs experiments across message sizes and thread counts
# 4. Collects profiling output using perf
# 5. Stores results in CSV format

set -e  # Exit on error

# Configuration
DURATION=10                           # Test duration in seconds
PORT=8080                             # Server port
SERVER_IP="10.0.0.1"                  # Server IP in namespace
CLIENT_IP="10.0.0.2"                  # Client IP in namespace

# Message sizes to test (in bytes) - total message size (8 fields)
MSG_SIZES=(1024 4096 16384 65536)

# Thread counts to test
THREAD_COUNTS=(1 2 4 8)

# Output directory for results
OUTPUT_DIR="results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="${OUTPUT_DIR}/MT25033_Part_B_Results_${TIMESTAMP}.csv"

# Perf events to collect
PERF_EVENTS="cycles,instructions,cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,context-switches"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (needed for namespaces and perf)
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root for network namespaces and perf"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

# Compile all implementations
compile_all() {
    log_info "Compiling all implementations..."
    make clean
    make all
    log_info "Compilation complete"
}

# Set up network namespaces
setup_namespaces() {
    log_info "Setting up network namespaces..."

    # Clean up existing namespaces if they exist
    ip netns del server_ns 2>/dev/null || true
    ip netns del client_ns 2>/dev/null || true

    # Create namespaces
    ip netns add server_ns
    ip netns add client_ns

    # Create veth pair
    ip link add veth-server type veth peer name veth-client

    # Move interfaces to namespaces
    ip link set veth-server netns server_ns
    ip link set veth-client netns client_ns

    # Configure interfaces in server namespace
    ip netns exec server_ns ip addr add ${SERVER_IP}/24 dev veth-server
    ip netns exec server_ns ip link set veth-server up
    ip netns exec server_ns ip link set lo up

    # Configure interfaces in client namespace
    ip netns exec client_ns ip addr add ${CLIENT_IP}/24 dev veth-client
    ip netns exec client_ns ip link set veth-client up
    ip netns exec client_ns ip link set lo up

    log_info "Network namespaces configured"
    log_info "  Server namespace: server_ns (${SERVER_IP})"
    log_info "  Client namespace: client_ns (${CLIENT_IP})"
}

# Clean up network namespaces
cleanup_namespaces() {
    log_info "Cleaning up network namespaces..."
    ip netns del server_ns 2>/dev/null || true
    ip netns del client_ns 2>/dev/null || true
    log_info "Namespaces cleaned up"
}

# Initialize CSV file with headers
init_csv() {
    mkdir -p ${OUTPUT_DIR}
    echo "implementation,msg_size,threads,throughput_gbps,latency_us,total_bytes,cycles,instructions,cache_refs,cache_misses,l1_loads,l1_misses,llc_loads,llc_misses,context_switches" > ${CSV_FILE}
    log_info "CSV file initialized: ${CSV_FILE}"
}

# Run a single experiment
run_experiment() {
    local impl_name=$1
    local server_bin=$2
    local client_bin=$3
    local msg_size=$4
    local threads=$5

    log_info "Running: ${impl_name}, msg_size=${msg_size}, threads=${threads}"

    local perf_output="${OUTPUT_DIR}/perf_${impl_name}_${msg_size}_${threads}.txt"
    local server_output="${OUTPUT_DIR}/server_${impl_name}_${msg_size}_${threads}.txt"
    local client_output="${OUTPUT_DIR}/client_${impl_name}_${msg_size}_${threads}.txt"

    # Start client FIRST in client namespace (receiver)
    ip netns exec client_ns ./${client_bin} -i ${SERVER_IP} -p ${PORT} -s ${msg_size} -t ${threads} -d $((DURATION + 5)) > ${client_output} 2>&1 &
    local client_pid=$!

    # Wait for client to be ready
    sleep 2

    # Run server with perf in server namespace (sender - where copy optimization happens)
    ip netns exec server_ns perf stat -e ${PERF_EVENTS} -o ${perf_output} \
        ./${server_bin} -p ${PORT} -s ${msg_size} -d ${DURATION} > ${server_output} 2>&1

    # Kill client
    kill ${client_pid} 2>/dev/null || true
    wait ${client_pid} 2>/dev/null || true

    # Parse results
    parse_results "${impl_name}" "${msg_size}" "${threads}" "${client_output}" "${perf_output}"

    # Small delay between experiments
    sleep 1
}

# Parse results and append to CSV
parse_results() {
    local impl_name=$1
    local msg_size=$2
    local threads=$3
    local client_output=$4
    local perf_output=$5

    # Extract metrics from client output (CSV line)
    local csv_line=$(grep "^CSV:" ${client_output} | tail -1 | cut -d':' -f2 | tr -d ' ')
    local throughput=$(echo ${csv_line} | cut -d',' -f4)
    local latency=$(echo ${csv_line} | cut -d',' -f5)
    local total_bytes=$(echo ${csv_line} | cut -d',' -f6)

    # Extract perf metrics
    local cycles=$(grep -E "^\s*[0-9,]+\s+cycles" ${perf_output} | awk '{print $1}' | tr -d ',')
    local instructions=$(grep -E "^\s*[0-9,]+\s+instructions" ${perf_output} | awk '{print $1}' | tr -d ',')
    local cache_refs=$(grep "cache-references" ${perf_output} | awk '{print $1}' | tr -d ',')
    local cache_misses=$(grep "cache-misses" ${perf_output} | awk '{print $1}' | tr -d ',')
    local l1_loads=$(grep "L1-dcache-loads" ${perf_output} | awk '{print $1}' | tr -d ',')
    local l1_misses=$(grep "L1-dcache-load-misses" ${perf_output} | awk '{print $1}' | tr -d ',')
    local llc_loads=$(grep "LLC-loads" ${perf_output} | awk '{print $1}' | tr -d ',')
    local llc_misses=$(grep "LLC-load-misses" ${perf_output} | awk '{print $1}' | tr -d ',')
    local ctx_switches=$(grep "context-switches" ${perf_output} | awk '{print $1}' | tr -d ',')

    # Set defaults for missing values
    cycles=${cycles:-0}
    instructions=${instructions:-0}
    cache_refs=${cache_refs:-0}
    cache_misses=${cache_misses:-0}
    l1_loads=${l1_loads:-0}
    l1_misses=${l1_misses:-0}
    llc_loads=${llc_loads:-0}
    llc_misses=${llc_misses:-0}
    ctx_switches=${ctx_switches:-0}

    # Append to CSV
    echo "${impl_name},${msg_size},${threads},${throughput},${latency},${total_bytes},${cycles},${instructions},${cache_refs},${cache_misses},${l1_loads},${l1_misses},${llc_loads},${llc_misses},${ctx_switches}" >> ${CSV_FILE}

    log_info "  Throughput: ${throughput} Gbps, Latency: ${latency} µs"
}

# Run all experiments for an implementation
run_all_experiments() {
    local impl_name=$1
    local server_bin=$2
    local client_bin=$3

    log_info "=========================================="
    log_info "Testing: ${impl_name}"
    log_info "=========================================="

    for msg_size in "${MSG_SIZES[@]}"; do
        for threads in "${THREAD_COUNTS[@]}"; do
            run_experiment "${impl_name}" "${server_bin}" "${client_bin}" "${msg_size}" "${threads}"
        done
    done
}

# Main execution
main() {
    log_info "PA02: Network I/O Analysis - Automated Experiment Script"
    log_info "Roll Number: MT25033"
    log_info "=========================================="

    # Check root
    check_root

    # Compile
    compile_all

    # Set up namespaces
    setup_namespaces

    # Initialize CSV
    init_csv

    # Run experiments for each implementation
    run_all_experiments "two_copy" "MT25033_Part_A1_Server" "MT25033_Part_A1_Client"
    run_all_experiments "one_copy" "MT25033_Part_A2_Server" "MT25033_Part_A2_Client"
    run_all_experiments "zero_copy" "MT25033_Part_A3_Server" "MT25033_Part_A3_Client"

    # Cleanup
    cleanup_namespaces

    log_info "=========================================="
    log_info "All experiments completed!"
    log_info "Results saved to: ${CSV_FILE}"
    log_info "=========================================="

    # Display summary
    echo ""
    log_info "CSV Summary:"
    cat ${CSV_FILE}
}

# Trap to ensure cleanup on exit
trap cleanup_namespaces EXIT

# Run main
main "$@"
