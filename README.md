# MT25033
# PA02: Analysis of Network I/O Primitives using "perf" tool
# Roll Number: MT25033
# Course: CSE638 - Graduate Systems
# Institution: IIIT Delhi

---

## Objective

This project experimentally studies the cost of data movement in network I/O by implementing and comparing:
- **Two-Copy**: Standard socket communication using `send()`/`recv()`
- **One-Copy**: Optimized socket communication using `sendmsg()` with iovec
- **Zero-Copy**: Zero-copy communication using `sendmsg()` with `MSG_ZEROCOPY`

---

## File Structure

```
MT25033_PA02/
├── MT25033_Part_A_Common.h           # Common header with Message struct (8 fields)
├── MT25033_Part_A1_Server.c          # Two-copy server using send()
├── MT25033_Part_A1_Client.c          # Two-copy client using recv()
├── MT25033_Part_A2_Server.c          # One-copy server using sendmsg()
├── MT25033_Part_A2_Client.c          # One-copy client using recvmsg()
├── MT25033_Part_A3_Server.c          # Zero-copy server using MSG_ZEROCOPY
├── MT25033_Part_A3_Client.c          # Zero-copy client
├── MT25033_Part_B_Combined.csv       # Combined profiling results
├── MT25033_Part_B_TwoCopy.csv        # Two-copy results
├── MT25033_Part_B_OneCopy.csv        # One-copy results
├── MT25033_Part_B_ZeroCopy.csv       # Zero-copy results
├── MT25033_Part_C_Experiment.sh      # Automated experiment script
├── MT25033_Part_D_Plots.py           # Matplotlib plotting (hardcoded values)
├── MT25033_Menu.sh                   # Interactive menu for running experiments
├── Makefile                          # Build configuration
└── README.md                         # This file
```

---

## Quick Start

### 1. Compile
```bash
make clean
make
```

### 2. Run (with menu)
```bash
sudo make run
```

This will:
- Compile all programs
- Set up network namespaces automatically
- Show interactive menu
- Clean up namespaces on exit

---

## Manual Usage

### Command Line Arguments

**Server:**
```
-p <port>      Port number (default: 8080)
-s <size>      Message size in bytes (default: 1024)
-d <duration>  Test duration in seconds (default: 10)
-h             Show help
```

**Client:**
```
-i <ip>        Server IP address (default: 127.0.0.1)
-p <port>      Server port (default: 8080)
-s <size>      Message size in bytes (default: 1024)
-t <threads>   Number of client threads (default: 4)
-d <duration>  Test duration in seconds (default: 10)
-h             Show help
```

### Example - Running Two-Copy

```bash
# Terminal 1 (Server)
./MT25033_Part_A1_Server -p 8080 -s 4096 -d 30

# Terminal 2 (Client)
./MT25033_Part_A1_Client -i 127.0.0.1 -p 8080 -s 4096 -t 4 -d 30
```

---

## Running with Network Namespaces

As per assignment requirements, client and server must run in separate namespaces.

### Manual Setup
```bash
# Create namespaces
sudo ip netns add server_ns
sudo ip netns add client_ns

# Create veth pair
sudo ip link add veth-server type veth peer name veth-client
sudo ip link set veth-server netns server_ns
sudo ip link set veth-client netns client_ns

# Configure IPs
sudo ip netns exec server_ns ip addr add 10.0.0.1/24 dev veth-server
sudo ip netns exec server_ns ip link set veth-server up
sudo ip netns exec server_ns ip link set lo up

sudo ip netns exec client_ns ip addr add 10.0.0.2/24 dev veth-client
sudo ip netns exec client_ns ip link set veth-client up
sudo ip netns exec client_ns ip link set lo up

# Run
sudo ip netns exec server_ns ./MT25033_Part_A1_Server -p 8080 -s 4096 -d 30
sudo ip netns exec client_ns ./MT25033_Part_A1_Client -i 10.0.0.1 -p 8080 -s 4096 -t 4 -d 30
```

---

## Profiling with perf

```bash
# Enable perf access
sudo sysctl kernel.perf_event_paranoid=-1

# Run with perf stat
perf stat -e cycles,cache-misses,cache-references,context-switches \
    ./MT25033_Part_A1_Server -p 8080 -s 4096 -d 10
```

---

## Generating Plots

```bash
# Install dependencies
pip3 install matplotlib numpy pandas

# Run plotting script (values are hardcoded)
python3 MT25033_Part_D_Plots.py
```

**Note:** As per assignment requirements, values in the plotting script are HARDCODED. Update the arrays in the script with your experimental results before generating final plots.

---

## Implementation Details

### A1: Two-Copy Implementation
- Uses `send()`/`recv()` syscalls
- **Copy 1:** User buffer → Kernel socket buffer
- **Copy 2:** Kernel socket buffer → NIC DMA buffer

### A2: One-Copy Implementation
- Uses `sendmsg()`/`recvmsg()` with iovec (scatter-gather I/O)
- Kernel gathers data from multiple user buffers directly
- Eliminates intermediate copy in user space

### A3: Zero-Copy Implementation
- Uses `sendmsg()` with `MSG_ZEROCOPY` flag
- Kernel pins user pages and DMAs directly from user space
- Requires Linux kernel 4.14+ and `SO_ZEROCOPY` socket option

---

## Dependencies

- GCC compiler with pthread support
- Linux kernel 4.14+ (for MSG_ZEROCOPY)
- perf tools (`linux-tools-generic`)
- Python 3.x with matplotlib, numpy, pandas

### Install on Ubuntu/Debian
```bash
sudo apt update
sudo apt install build-essential linux-tools-generic python3-matplotlib python3-numpy python3-pandas
```

---

## CSV Output Format

```
Implementation,MessageSize,Threads,Throughput_Gbps,Latency_us,TotalBytes,CPUCycles,CyclesPerByte,CacheMisses,CacheRefs,ContextSwitches
```

---

## AI Usage Declaration

This project was developed with assistance from Claude (Anthropic). The following components used AI assistance:
- Socket implementation structure and boilerplate code
- Perf event configuration for hybrid CPUs
- Bash script for automated experiments
- Matplotlib plotting script structure

All code has been reviewed, understood, and can be explained during viva.


---

## Author

- **Roll Number:** MT25033
- **Course:** CSE638 - Graduate Systems
- **Institution:** IIIT Delhi
