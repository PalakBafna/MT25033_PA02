#!/usr/bin/env python3
"""
MT25033_Part_D_Plots.py
Matplotlib Plotting Script for PA02: Network I/O Analysis
Roll Number: MT25033
"""

import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import os
import sys

# ============================================================================
# CONFIGURATION
# ============================================================================

CSV_DIR = "results"
OUTPUT_DIR = "."  # Save plots in current directory

# Colors
COLORS = {'A1': '#3498db', 'A2': '#2ecc71', 'A3': '#e74c3c'}
LABELS = {'A1': 'Two-Copy', 'A2': 'One-Copy', 'A3': 'Zero-Copy'}

def get_size_label(size):
    """Convert bytes to human readable."""
    if size >= 1048576:
        return f'{size//1048576}MB'
    elif size >= 1024:
        return f'{size//1024}KB'
    return f'{size}B'

# ============================================================================
# LOAD DATA
# ============================================================================

def load_data():
    """Load CSV data."""
    data = {}

    files = {
        'A1': f'{CSV_DIR}/MT25033_Part_B_TwoCopy.csv',
        'A2': f'{CSV_DIR}/MT25033_Part_B_OneCopy.csv',
        'A3': f'{CSV_DIR}/MT25033_Part_B_ZeroCopy.csv'
    }

    for impl, path in files.items():
        if os.path.exists(path):
            try:
                df = pd.read_csv(path)
                data[impl] = df
                print(f"  Loaded {impl}: {len(df)} rows from {path}")
            except Exception as e:
                print(f"  Error loading {path}: {e}")
        else:
            print(f"  File not found: {path}")

    return data

# ============================================================================
# PLOTTING
# ============================================================================

def plot_throughput(data):
    """Plot 1: Throughput vs Message Size."""
    print("  Creating throughput plot...")

    fig, ax = plt.subplots(figsize=(12, 7))

    width = 0.25
    x_labels = None
    x = None

    for i, (impl, df) in enumerate(data.items()):
        # Filter for 4 threads
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')

        sizes = d['MessageSize'].values
        throughput = d['Throughput_Gbps'].values

        if x is None:
            x = np.arange(len(sizes))
            x_labels = [get_size_label(s) for s in sizes]

        offset = (i - 1) * width
        ax.bar(x + offset, throughput, width, label=LABELS[impl], color=COLORS[impl])

    ax.set_xlabel('Message Size')
    ax.set_ylabel('Throughput (Gbps)')
    ax.set_title('Throughput vs Message Size (4 Threads)\nMT25033')
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    path = f'{OUTPUT_DIR}/MT25033_Plot1_Throughput.png'
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"    Saved: {path}")


def plot_latency(data):
    """Plot 2: Latency vs Threads."""
    print("  Creating latency plot...")

    fig, ax = plt.subplots(figsize=(10, 6))

    markers = {'A1': 'o', 'A2': 's', 'A3': '^'}

    for impl, df in data.items():
        # Filter for 64KB message size (or closest)
        sizes = df['MessageSize'].unique()
        target = 65536 if 65536 in sizes else sizes[len(sizes)//2]
        d = df[df['MessageSize'] == target].sort_values('Threads')

        if len(d) > 0:
            ax.plot(d['Threads'], d['Latency_us'], f'{markers[impl]}-',
                   linewidth=2, markersize=8, label=LABELS[impl], color=COLORS[impl])

    ax.set_xlabel('Number of Threads')
    ax.set_ylabel('Latency (us)')
    ax.set_title('Latency vs Thread Count\nMT25033')
    ax.legend()
    ax.grid(alpha=0.3)

    plt.tight_layout()
    path = f'{OUTPUT_DIR}/MT25033_Plot2_Latency.png'
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"    Saved: {path}")


def plot_cache(data):
    """Plot 3: Cache Misses and References."""
    print("  Creating cache plot...")

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    width = 0.25
    x_labels = None
    x = None

    for i, (impl, df) in enumerate(data.items()):
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')

        sizes = d['MessageSize'].values

        if x is None:
            x = np.arange(len(sizes))
            x_labels = [get_size_label(s) for s in sizes]

        offset = (i - 1) * width

        # Cache Misses
        if 'CacheMisses' in d.columns:
            misses = d['CacheMisses'].values / 1000
            ax1.bar(x + offset, misses, width, label=LABELS[impl], color=COLORS[impl])

        # Cache References
        if 'CacheRefs' in d.columns:
            refs = d['CacheRefs'].values / 1000
            ax2.bar(x + offset, refs, width, label=LABELS[impl], color=COLORS[impl])

    ax1.set_xlabel('Message Size')
    ax1.set_ylabel('Cache Misses (K)')
    ax1.set_title('Cache Misses')
    ax1.set_xticks(x)
    ax1.set_xticklabels(x_labels)
    ax1.legend()
    ax1.grid(axis='y', alpha=0.3)

    ax2.set_xlabel('Message Size')
    ax2.set_ylabel('Cache References (K)')
    ax2.set_title('Cache References')
    ax2.set_xticks(x)
    ax2.set_xticklabels(x_labels)
    ax2.legend()
    ax2.grid(axis='y', alpha=0.3)

    plt.suptitle('Cache Performance (4 Threads) - MT25033', fontsize=14)
    plt.tight_layout()
    path = f'{OUTPUT_DIR}/MT25033_Plot3_Cache.png'
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"    Saved: {path}")


def plot_overhead(data):
    """Plot 4: CPU Cycles per Byte (Overhead)."""
    print("  Creating overhead plot...")

    fig, ax = plt.subplots(figsize=(12, 7))

    markers = {'A1': 'o', 'A2': 's', 'A3': '^'}
    x_labels = None

    for impl, df in data.items():
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')

        sizes = d['MessageSize'].values

        if x_labels is None:
            x_labels = [get_size_label(s) for s in sizes]

        if 'CyclesPerByte' in d.columns:
            cpb = d['CyclesPerByte'].values
            ax.plot(range(len(cpb)), cpb, f'{markers[impl]}-',
                   linewidth=2, markersize=8, label=LABELS[impl], color=COLORS[impl])

    ax.set_xlabel('Message Size')
    ax.set_ylabel('CPU Cycles per Byte (Lower = Better)')
    ax.set_title('CPU Overhead: Cycles per Byte (4 Threads)\nMT25033')
    ax.set_xticks(range(len(x_labels)))
    ax.set_xticklabels(x_labels)
    ax.legend()
    ax.grid(alpha=0.3)

    plt.tight_layout()
    path = f'{OUTPUT_DIR}/MT25033_Plot4_Overhead.png'
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"    Saved: {path}")


def plot_context_switches(data):
    """Plot 5: Context Switches."""
    print("  Creating context switches plot...")

    fig, ax = plt.subplots(figsize=(12, 7))

    width = 0.25
    x_labels = None
    x = None

    for i, (impl, df) in enumerate(data.items()):
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')

        sizes = d['MessageSize'].values

        if x is None:
            x = np.arange(len(sizes))
            x_labels = [get_size_label(s) for s in sizes]

        offset = (i - 1) * width

        if 'ContextSwitches' in d.columns:
            ctx = d['ContextSwitches'].values
            ax.bar(x + offset, ctx, width, label=LABELS[impl], color=COLORS[impl])

    ax.set_xlabel('Message Size')
    ax.set_ylabel('Context Switches')
    ax.set_title('Context Switches vs Message Size (4 Threads)\nMT25033')
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    path = f'{OUTPUT_DIR}/MT25033_Plot5_ContextSwitches.png'
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"    Saved: {path}")


def plot_summary(data):
    """Plot 6: Combined Summary (2x3 grid)."""
    print("  Creating summary plot...")

    fig, axes = plt.subplots(2, 3, figsize=(16, 10))

    width = 0.25
    markers = {'A1': 'o', 'A2': 's', 'A3': '^'}

    # Get common x values
    x_labels = None
    x = None
    for impl, df in data.items():
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')
        sizes = d['MessageSize'].values
        x = np.arange(len(sizes))
        x_labels = [get_size_label(s) for s in sizes]
        break

    # 1. Throughput
    ax = axes[0, 0]
    for i, (impl, df) in enumerate(data.items()):
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')
        offset = (i - 1) * width
        ax.bar(x + offset, d['Throughput_Gbps'].values, width, label=LABELS[impl], color=COLORS[impl])
    ax.set_title('Throughput (Gbps)')
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels, fontsize=8)
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    # 2. Latency
    ax = axes[0, 1]
    for impl, df in data.items():
        sizes = df['MessageSize'].unique()
        target = 65536 if 65536 in sizes else sizes[len(sizes)//2]
        d = df[df['MessageSize'] == target].sort_values('Threads')
        if len(d) > 0:
            ax.plot(d['Threads'], d['Latency_us'], f'{markers[impl]}-',
                   linewidth=2, markersize=6, label=LABELS[impl], color=COLORS[impl])
    ax.set_title('Latency (us)')
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # 3. Overhead
    ax = axes[0, 2]
    for impl, df in data.items():
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')
        if 'CyclesPerByte' in d.columns:
            ax.plot(range(len(d)), d['CyclesPerByte'].values, f'{markers[impl]}-',
                   linewidth=2, markersize=6, label=LABELS[impl], color=COLORS[impl])
    ax.set_title('Cycles/Byte (Overhead)')
    ax.set_xticks(range(len(x_labels)))
    ax.set_xticklabels(x_labels, fontsize=8)
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # 4. Cache Misses
    ax = axes[1, 0]
    for i, (impl, df) in enumerate(data.items()):
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')
        offset = (i - 1) * width
        if 'CacheMisses' in d.columns:
            ax.bar(x + offset, d['CacheMisses'].values/1000, width, label=LABELS[impl], color=COLORS[impl])
    ax.set_title('Cache Misses (K)')
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels, fontsize=8)
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    # 5. Cache References
    ax = axes[1, 1]
    for i, (impl, df) in enumerate(data.items()):
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')
        offset = (i - 1) * width
        if 'CacheRefs' in d.columns:
            ax.bar(x + offset, d['CacheRefs'].values/1000, width, label=LABELS[impl], color=COLORS[impl])
    ax.set_title('Cache Refs (K)')
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels, fontsize=8)
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    # 6. Context Switches
    ax = axes[1, 2]
    for i, (impl, df) in enumerate(data.items()):
        d = df[df['Threads'] == 4].sort_values('MessageSize')
        if len(d) == 0:
            d = df.sort_values('MessageSize').drop_duplicates('MessageSize')
        offset = (i - 1) * width
        if 'ContextSwitches' in d.columns:
            ax.bar(x + offset, d['ContextSwitches'].values, width, label=LABELS[impl], color=COLORS[impl])
    ax.set_title('Context Switches')
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels, fontsize=8)
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    plt.suptitle('PA02: Network I/O Performance Summary - MT25033', fontsize=14)
    plt.tight_layout()
    path = f'{OUTPUT_DIR}/MT25033_Plot6_Summary.png'
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"    Saved: {path}")


# ============================================================================
# MAIN
# ============================================================================

def main():
    print("="*60)
    print("PA02: Network I/O Analysis - Plot Generation")
    print("Roll Number: MT25033")
    print("="*60)
    print()

    # Check if results directory exists
    if not os.path.exists(CSV_DIR):
        print(f"ERROR: {CSV_DIR}/ directory not found!")
        print("Run Part B first to generate CSV files.")
        sys.exit(1)

    # Load data
    print("Loading CSV data...")
    data = load_data()

    if not data:
        print("\nERROR: No data loaded!")
        print("Make sure CSV files exist in results/ directory.")
        sys.exit(1)

    # Show columns
    print("\nCSV Columns found:")
    for impl, df in data.items():
        print(f"  {impl}: {list(df.columns)}")

    # Generate plots
    print("\n" + "="*60)
    print("Generating plots...")
    print("="*60)

    try:
        plot_throughput(data)
    except Exception as e:
        print(f"  ERROR in throughput plot: {e}")

    try:
        plot_latency(data)
    except Exception as e:
        print(f"  ERROR in latency plot: {e}")

    try:
        plot_cache(data)
    except Exception as e:
        print(f"  ERROR in cache plot: {e}")

    try:
        plot_overhead(data)
    except Exception as e:
        print(f"  ERROR in overhead plot: {e}")

    try:
        plot_context_switches(data)
    except Exception as e:
        print(f"  ERROR in context switches plot: {e}")

    try:
        plot_summary(data)
    except Exception as e:
        print(f"  ERROR in summary plot: {e}")

    print("\n" + "="*60)
    print("DONE! Check for PNG files:")
    print("="*60)

    # List generated files
    for f in os.listdir('.'):
        if f.endswith('.png') and 'MT25033' in f:
            print(f"  {f}")

    print()

if __name__ == "__main__":
    main()
