# MT25033
# Makefile for PA02: Analysis of Network I/O primitives
# Roll Number: MT25033
#
# Usage:
#   make clean  - Delete all compiled files
#   make        - Compile all programs
#   make run    - Setup namespaces, compile, and show menu

CC = gcc
CFLAGS = -Wall -Wextra -O2 -pthread
LDFLAGS = -pthread

# Source files
COMMON_HDR = MT25033_Part_A_Common.h

# Two-Copy (A1)
A1_SERVER = MT25033_Part_A1_Server
A1_CLIENT = MT25033_Part_A1_Client

# One-Copy (A2)
A2_SERVER = MT25033_Part_A2_Server
A2_CLIENT = MT25033_Part_A2_Client

# Zero-Copy (A3)
A3_SERVER = MT25033_Part_A3_Server
A3_CLIENT = MT25033_Part_A3_Client

# All targets
TARGETS = $(A1_SERVER) $(A1_CLIENT) $(A2_SERVER) $(A2_CLIENT) $(A3_SERVER) $(A3_CLIENT)

.PHONY: all clean help run setup-ns cleanup-ns

# Default target: compile all
all: $(TARGETS)
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo "  BUILD COMPLETE - MT25033"
	@echo "════════════════════════════════════════════════════════════"
	@echo "  Two-Copy:  $(A1_SERVER), $(A1_CLIENT)"
	@echo "  One-Copy:  $(A2_SERVER), $(A2_CLIENT)"
	@echo "  Zero-Copy: $(A3_SERVER), $(A3_CLIENT)"
	@echo ""
	@echo "  Next: Run 'sudo make run' to start the menu"
	@echo "════════════════════════════════════════════════════════════"

# Two-Copy Implementation (A1)
$(A1_SERVER): $(A1_SERVER).c $(COMMON_HDR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(A1_CLIENT): $(A1_CLIENT).c $(COMMON_HDR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# One-Copy Implementation (A2)
$(A2_SERVER): $(A2_SERVER).c $(COMMON_HDR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(A2_CLIENT): $(A2_CLIENT).c $(COMMON_HDR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Zero-Copy Implementation (A3)
$(A3_SERVER): $(A3_SERVER).c $(COMMON_HDR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(A3_CLIENT): $(A3_CLIENT).c $(COMMON_HDR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Clean all compiled files and results
# Note: results/ may need sudo to delete (created by sudo make run)
clean:
	@echo "Cleaning..."
	rm -f $(TARGETS)
	rm -f *.o
	rm -f *.png
	@if [ -d "results" ]; then \
		if rm -rf results/ 2>/dev/null; then \
			echo "Deleted results/"; \
		else \
			echo "results/ needs sudo to delete (run: sudo rm -rf results/)"; \
		fi; \
	fi
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo "  CLEAN COMPLETE"
	@echo "════════════════════════════════════════════════════════════"
	@echo "  Deleted: executables, object files, plots"
	@echo "  Note: Use 'sudo make clean' to also delete results/"
	@echo "════════════════════════════════════════════════════════════"

# Setup network namespaces
setup-ns:
	@echo "Setting up network namespaces..."
	@ip netns del server_ns 2>/dev/null || true
	@ip netns del client_ns 2>/dev/null || true
	@ip link del veth-server 2>/dev/null || true
	@ip netns add server_ns
	@ip netns add client_ns
	@ip link add veth-server type veth peer name veth-client
	@ip link set veth-server netns server_ns
	@ip link set veth-client netns client_ns
	@ip netns exec server_ns ip addr add 10.0.0.1/24 dev veth-server
	@ip netns exec server_ns ip link set veth-server up
	@ip netns exec server_ns ip link set lo up
	@ip netns exec client_ns ip addr add 10.0.0.2/24 dev veth-client
	@ip netns exec client_ns ip link set veth-client up
	@ip netns exec client_ns ip link set lo up
	@echo "Network namespaces ready: server_ns (10.0.0.1), client_ns (10.0.0.2)"

# Cleanup network namespaces
cleanup-ns:
	@echo "Cleaning up network namespaces..."
	@ip netns del server_ns 2>/dev/null || true
	@ip netns del client_ns 2>/dev/null || true
	@echo "Network namespaces deleted"

# Run: compile, setup namespaces, show menu
run: all setup-ns
	@echo ""
	@echo "Starting menu..."
	@chmod +x MT25033_Menu.sh
	@./MT25033_Menu.sh; \
	echo ""; \
	echo "Cleaning up namespaces..."; \
	ip netns del server_ns 2>/dev/null || true; \
	ip netns del client_ns 2>/dev/null || true; \
	echo "Done!"

# Help
help:
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo "  PA02: Network I/O Analysis - MT25033"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Usage:"
	@echo "    make clean    - Delete all compiled files and results"
	@echo "    make          - Compile all server/client programs"
	@echo "    sudo make run - Compile, setup namespaces, show menu"
	@echo ""
	@echo "  Programs:"
	@echo "    $(A1_SERVER) / $(A1_CLIENT) - Two-copy (send/recv)"
	@echo "    $(A2_SERVER) / $(A2_CLIENT) - One-copy (sendmsg)"
	@echo "    $(A3_SERVER) / $(A3_CLIENT) - Zero-copy (MSG_ZEROCOPY)"
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
