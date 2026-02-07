#!/bin/bash
# MT25033
# MT25033_Menu.sh - Assignment Menu
# Roll Number: MT25033
#
# NOTE: Run with 'sudo make run' which handles compilation and namespace setup

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
PORT=8080
SERVER_IP="10.0.0.1"

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     PA02: Analysis of Network I/O Primitives                 ║"
    echo "║     Roll Number: MT25033                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Get parameters from user
get_params() {
    echo ""
    read -p "Message size in bytes [1024]: " msg_size
    msg_size=${msg_size:-1024}

    read -p "Number of threads [4]: " threads
    threads=${threads:-4}

    read -p "Duration in seconds [10]: " duration
    duration=${duration:-10}

    echo ""
    echo -e "${GREEN}Parameters: size=$msg_size, threads=$threads, duration=$duration${NC}"
    echo ""
}

# ============================================================================
# PART A1: Two-Copy Implementation
# ============================================================================
run_part_a1() {
    print_banner
    echo -e "${BOLD}PART A1: Two-Copy Implementation (send/recv)${NC}"
    echo ""
    echo "This uses standard send()/recv() socket primitives."
    echo "Two copies occur: User→Kernel and Kernel→NIC"
    echo ""

    get_params

    mkdir -p results

    echo -e "${YELLOW}[1/3] Starting Server with PERF (sender) in background...${NC}"
    ip netns exec server_ns perf stat -e cycles,cache-misses,cache-references,context-switches \
        ./MT25033_Part_A1_Server -p $PORT -s $msg_size -d $duration > results/a1_server.txt 2>&1 &
    SERVER_PID=$!
    sleep 2

    echo -e "${YELLOW}[2/3] Starting Client (receiver)...${NC}"
    echo ""
    ip netns exec client_ns ./MT25033_Part_A1_Client -i $SERVER_IP -p $PORT -s $msg_size -t $threads -d $duration 2>&1 | tee results/a1_client.txt

    echo ""
    echo -e "${YELLOW}[3/3] Waiting for server to finish...${NC}"
    wait $SERVER_PID 2>/dev/null

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}PART A1 COMPLETE - Results saved to results/${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Server perf output:${NC}"
    cat results/a1_server.txt | grep -E "cycles|instructions|cache|context"
    echo ""

    read -p "Press Enter to continue..."
}

# ============================================================================
# PART A2: One-Copy Implementation
# ============================================================================
run_part_a2() {
    print_banner
    echo -e "${BOLD}PART A2: One-Copy Implementation (sendmsg/iovec)${NC}"
    echo ""
    echo "This uses sendmsg() with scatter-gather I/O (iovec)."
    echo "One copy eliminated: No contiguous buffer copy needed."
    echo ""

    get_params

    mkdir -p results

    echo -e "${YELLOW}[1/3] Starting Server with PERF (sender) in background...${NC}"
    ip netns exec server_ns perf stat -e cycles,cache-misses,cache-references,context-switches \
        ./MT25033_Part_A2_Server -p $PORT -s $msg_size -d $duration > results/a2_server.txt 2>&1 &
    SERVER_PID=$!
    sleep 2

    echo -e "${YELLOW}[2/3] Starting Client (receiver)...${NC}"
    echo ""
    ip netns exec client_ns ./MT25033_Part_A2_Client -i $SERVER_IP -p $PORT -s $msg_size -t $threads -d $duration 2>&1 | tee results/a2_client.txt

    echo ""
    echo -e "${YELLOW}[3/3] Waiting for server to finish...${NC}"
    wait $SERVER_PID 2>/dev/null

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}PART A2 COMPLETE - Results saved to results/${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Server perf output:${NC}"
    cat results/a2_server.txt | grep -E "cycles|instructions|cache|context"
    echo ""

    read -p "Press Enter to continue..."
}

# ============================================================================
# PART A3: Zero-Copy Implementation
# ============================================================================
run_part_a3() {
    print_banner
    echo -e "${BOLD}PART A3: Zero-Copy Implementation (MSG_ZEROCOPY)${NC}"
    echo ""
    echo "This uses sendmsg() with MSG_ZEROCOPY flag."
    echo "Zero copies: Kernel pins pages, NIC DMAs directly from user buffer."
    echo ""

    get_params

    mkdir -p results

    echo -e "${YELLOW}[1/3] Starting Server with PERF (sender) in background...${NC}"
    ip netns exec server_ns perf stat -e cycles,cache-misses,cache-references,context-switches \
        ./MT25033_Part_A3_Server -p $PORT -s $msg_size -d $duration > results/a3_server.txt 2>&1 &
    SERVER_PID=$!
    sleep 2

    echo -e "${YELLOW}[2/3] Starting Client (receiver)...${NC}"
    echo ""
    ip netns exec client_ns ./MT25033_Part_A3_Client -i $SERVER_IP -p $PORT -s $msg_size -t $threads -d $duration 2>&1 | tee results/a3_client.txt

    echo ""
    echo -e "${YELLOW}[3/3] Waiting for server to finish...${NC}"
    wait $SERVER_PID 2>/dev/null

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}PART A3 COMPLETE - Results saved to results/${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Server perf output:${NC}"
    cat results/a3_server.txt | grep -E "cycles|instructions|cache|context"
    echo ""

    read -p "Press Enter to continue..."
}

# ============================================================================
# PART B: Run All Experiments and Generate CSV
# ============================================================================
run_part_b() {
    print_banner
    echo -e "${BOLD}PART B: Profile All Implementations${NC}"
    echo ""
    echo "This runs all implementations with different message sizes and thread counts."
    echo "Creates CSV files for analysis."
    echo ""

    # Message sizes (1KB to 16MB)
    MSG_SIZES=(1024 4096 65536 1048576 4194304 16777216)
    THREAD_COUNTS=(1 2 4 8)
    DURATION=10

    mkdir -p results

    # Create CSV files with headers
    echo "Implementation,MessageSize,Threads,Throughput_Gbps,Latency_us,TotalBytes,CPUCycles,CyclesPerByte,CacheMisses,CacheRefs,ContextSwitches" > results/MT25033_Part_B_Combined.csv
    echo "MessageSize,Threads,Throughput_Gbps,Latency_us,TotalBytes,CPUCycles,CyclesPerByte,CacheMisses,CacheRefs,ContextSwitches" > results/MT25033_Part_B_TwoCopy.csv
    echo "MessageSize,Threads,Throughput_Gbps,Latency_us,TotalBytes,CPUCycles,CyclesPerByte,CacheMisses,CacheRefs,ContextSwitches" > results/MT25033_Part_B_OneCopy.csv
    echo "MessageSize,Threads,Throughput_Gbps,Latency_us,TotalBytes,CPUCycles,CyclesPerByte,CacheMisses,CacheRefs,ContextSwitches" > results/MT25033_Part_B_ZeroCopy.csv

    for impl in "TwoCopy:A1:MT25033_Part_A1" "OneCopy:A2:MT25033_Part_A2" "ZeroCopy:A3:MT25033_Part_A3"; do
        IFS=':' read -r impl_file impl_short impl_prefix <<< "$impl"

        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║  Testing: ${BOLD}${impl_short} (${impl_file})${NC}${CYAN}                                      ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

        for msg_size in "${MSG_SIZES[@]}"; do
            for threads in "${THREAD_COUNTS[@]}"; do
                # Format message size for display
                if [ $msg_size -ge 1048576 ]; then
                    size_display="$((msg_size / 1048576))MB"
                elif [ $msg_size -ge 1024 ]; then
                    size_display="$((msg_size / 1024))KB"
                else
                    size_display="${msg_size}B"
                fi

                echo -ne "${YELLOW}  Running: ${impl_short} | size=${size_display} | threads=${threads} ... ${NC}"

                # Start SERVER first
                # Using generic perf event names (work on both hybrid and non-hybrid CPUs)
                ip netns exec server_ns perf stat -e cycles,cache-misses,cache-references,context-switches \
                    ./${impl_prefix}_Server -p $PORT -s $msg_size -d $DURATION > /tmp/server_out.txt 2>&1 &
                SERVER_PID=$!
                sleep 2

                # Start client
                ip netns exec client_ns ./${impl_prefix}_Client -i $SERVER_IP -p $PORT -s $msg_size -t $threads -d $DURATION > /tmp/client_out.txt 2>&1 &
                CLIENT_PID=$!

                # Wait for both
                wait $SERVER_PID 2>/dev/null
                kill $CLIENT_PID 2>/dev/null
                wait $CLIENT_PID 2>/dev/null

                # Parse CLIENT output
                CLIENT_OUT=$(cat /tmp/client_out.txt)
                throughput=$(echo "$CLIENT_OUT" | grep "Aggregate throughput" | awk '{print $3}')
                latency=$(echo "$CLIENT_OUT" | grep "Average latency" | awk '{print $3}')
                total_bytes=$(echo "$CLIENT_OUT" | grep "Total bytes" | awk '{print $4}')

                # Parse SERVER perf output
                SERVER_OUT=$(cat /tmp/server_out.txt)

                # Extract numbers - remove commas, get first number on line
                cycles=$(echo "$SERVER_OUT" | grep -E "cycles" | grep -v "insn" | head -1 | sed 's/,//g' | awk '{print $1}')
                cache_misses=$(echo "$SERVER_OUT" | grep "cache-misses" | head -1 | sed 's/,//g' | awk '{print $1}')
                cache_refs=$(echo "$SERVER_OUT" | grep "cache-references" | head -1 | sed 's/,//g' | awk '{print $1}')
                ctx_switches=$(echo "$SERVER_OUT" | grep "context-switches" | head -1 | sed 's/,//g' | awk '{print $1}')

                # Set defaults (handle empty or non-numeric values)
                throughput=${throughput:-0}
                latency=${latency:-0}
                total_bytes=${total_bytes:-0}
                # Clean and validate numeric values
                cycles=$(echo "$cycles" | grep -oE '^[0-9]+' || echo "0")
                cache_misses=$(echo "$cache_misses" | grep -oE '^[0-9]+' || echo "0")
                cache_refs=$(echo "$cache_refs" | grep -oE '^[0-9]+' || echo "0")
                ctx_switches=$(echo "$ctx_switches" | grep -oE '^[0-9]+' || echo "0")
                # Set to 0 if empty
                cycles=${cycles:-0}
                cache_misses=${cache_misses:-0}
                cache_refs=${cache_refs:-0}
                ctx_switches=${ctx_switches:-0}

                # Calculate overhead (cycles per byte)
                if [ "$total_bytes" -gt 0 ] && [ "$cycles" -gt 0 ]; then
                    cycles_per_byte=$(echo "scale=4; $cycles / $total_bytes" | bc)
                else
                    cycles_per_byte="0"
                fi

                # Save to CSV files
                echo "${impl_short},${msg_size},${threads},${throughput},${latency},${total_bytes},${cycles},${cycles_per_byte},${cache_misses},${cache_refs},${ctx_switches}" >> results/MT25033_Part_B_Combined.csv
                echo "${msg_size},${threads},${throughput},${latency},${total_bytes},${cycles},${cycles_per_byte},${cache_misses},${cache_refs},${ctx_switches}" >> results/MT25033_Part_B_${impl_file}.csv

                echo -e "${GREEN}✓ ${throughput} Gbps${NC}"
                sleep 1
            done
        done
    done

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    ${BOLD}PART B COMPLETE!${NC}${CYAN}                           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}CSV Files Created:${NC}"
    echo "  results/MT25033_Part_B_Combined.csv"
    echo "  results/MT25033_Part_B_TwoCopy.csv"
    echo "  results/MT25033_Part_B_OneCopy.csv"
    echo "  results/MT25033_Part_B_ZeroCopy.csv"
    echo ""

    # Show summary for each implementation
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                         RESULTS SUMMARY${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}A1 - Two-Copy (send/recv):${NC}"
    head -1 results/MT25033_Part_B_TwoCopy.csv | column -t -s ','
    tail -n +2 results/MT25033_Part_B_TwoCopy.csv | head -6 | column -t -s ','
    echo ""

    echo -e "${CYAN}A2 - One-Copy (sendmsg/iovec):${NC}"
    tail -n +2 results/MT25033_Part_B_OneCopy.csv | head -6 | column -t -s ','
    echo ""

    echo -e "${CYAN}A3 - Zero-Copy (MSG_ZEROCOPY):${NC}"
    tail -n +2 results/MT25033_Part_B_ZeroCopy.csv | head -6 | column -t -s ','
    echo ""

    read -p "Press Enter to continue..."
}

# ============================================================================
# PART D: Generate Plots
# ============================================================================
run_part_d() {
    print_banner
    echo -e "${BOLD}PART D: Generate Plots (Matplotlib)${NC}"
    echo ""

    if [ ! -f "MT25033_Part_D_Plots.py" ]; then
        echo -e "${RED}Error: MT25033_Part_D_Plots.py not found!${NC}"
        read -p "Press Enter to continue..."
        return
    fi

    echo "Options:"
    echo "  1) Use hardcoded values (default)"
    echo "  2) Read from CSV (results/MT25033_Part_B_Combined.csv)"
    echo ""
    read -p "Select option [1]: " plot_choice
    plot_choice=${plot_choice:-1}

    if [ "$plot_choice" = "2" ]; then
        # Enable CSV mode in script
        sed -i 's/USE_CSV = False/USE_CSV = True/' MT25033_Part_D_Plots.py
    else
        sed -i 's/USE_CSV = True/USE_CSV = False/' MT25033_Part_D_Plots.py
    fi

    echo ""
    echo -e "${YELLOW}Generating plots...${NC}"
    python3 MT25033_Part_D_Plots.py

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}PLOTS GENERATED!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    ls -la *.png 2>/dev/null
    echo ""

    read -p "Press Enter to continue..."
}

# ============================================================================
# View Results
# ============================================================================
view_results() {
    print_banner
    echo -e "${BOLD}View Results${NC}"
    echo ""

    if [ -d "results" ]; then
        echo -e "${CYAN}Files in results/:${NC}"
        ls -la results/
        echo ""

        echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                         ALL RESULTS${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""

        if [ -f "results/MT25033_Part_B_TwoCopy.csv" ]; then
            echo -e "${CYAN}══ A1 - Two-Copy (send/recv) ══${NC}"
            cat results/MT25033_Part_B_TwoCopy.csv | column -t -s ','
            echo ""
        fi

        if [ -f "results/MT25033_Part_B_OneCopy.csv" ]; then
            echo -e "${CYAN}══ A2 - One-Copy (sendmsg/iovec) ══${NC}"
            cat results/MT25033_Part_B_OneCopy.csv | column -t -s ','
            echo ""
        fi

        if [ -f "results/MT25033_Part_B_ZeroCopy.csv" ]; then
            echo -e "${CYAN}══ A3 - Zero-Copy (MSG_ZEROCOPY) ══${NC}"
            cat results/MT25033_Part_B_ZeroCopy.csv | column -t -s ','
            echo ""
        fi

        if [ ! -f "results/MT25033_Part_B_TwoCopy.csv" ]; then
            echo "No CSV results found. Run Part B first."
        fi
    else
        echo "No results directory found. Run Part B first."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# ============================================================================
# MAIN MENU
# ============================================================================
main_menu() {
    while true; do
        print_banner
        echo -e "${BOLD}  MENU${NC}"
        echo ""
        echo "  ┌─────────────────────────────────────────────────┐"
        echo "  │  1) Part A1: Two-Copy (send/recv)               │"
        echo "  │  2) Part A2: One-Copy (sendmsg/iovec)           │"
        echo "  │  3) Part A3: Zero-Copy (MSG_ZEROCOPY)           │"
        echo "  ├─────────────────────────────────────────────────┤"
        echo "  │  B) Part B: Profile All (generates CSV)         │"
        echo "  │  D) Part D: Generate Plots                      │"
        echo "  ├─────────────────────────────────────────────────┤"
        echo "  │  V) View Results                                │"
        echo "  │  Q) Quit                                        │"
        echo "  └─────────────────────────────────────────────────┘"
        echo ""
        read -p "  Select option: " choice

        case $choice in
            1) run_part_a1 ;;
            2) run_part_a2 ;;
            3) run_part_a3 ;;
            b|B) run_part_b ;;
            d|D) run_part_d ;;
            v|V) view_results ;;
            q|Q)
                echo ""
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# START
# ============================================================================

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run with: sudo make run${NC}"
    exit 1
fi

main_menu
