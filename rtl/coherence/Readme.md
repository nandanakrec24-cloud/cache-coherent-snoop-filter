Exclusive Negative Snoop Filter

Cache Coherence Mini Project — RTL Design using Verilog HDL

1. Overview

The Exclusive Negative Snoop Filter is a hardware module designed to optimize cache coherence operations in a multiprocessor system containing two private L1 caches.

In a conventional snooping-based cache coherence system, a cache may need to be checked whenever another processor requests or modifies a particular memory address. These snoop operations consume power, communication bandwidth, and processing resources.

The proposed Snoop Filter reduces unnecessary snoop operations by maintaining a record of memory addresses that are known to be absent from both private L1 caches.

If a queried address is present in the filter, the system can safely skip the remote snoop operation, provided the cache coherence integration protocol maintains the required invariants.

If the address is not present in the filter, the normal snooping mechanism is activated.

2. Objective

The primary objectives of this module are:

- To reduce unnecessary snoop requests between private L1 caches.
- To maintain information about addresses absent from both L1 caches.
- To provide a fast address lookup mechanism.
- To support insertion and removal of addresses dynamically.
- To implement a parameterized filter with configurable capacity.
- To ensure safe operation through proper update priority and reset handling.

3. Working Principle

This design implements an Exclusive Negative Filter.

Unlike a conventional positive snoop filter that tracks which cache contains a particular address, this design tracks addresses that are confirmed to be absent from BOTH private L1 caches.

The filter maintains two arrays:

1. "addr_mem": Stores the memory addresses.
2. "valid_mem": Indicates whether an entry contains valid negative information.

Lookup Operation

When a processor requests an address, the module compares the requested address against all valid entries.

- Filter Hit: The address is found in the filter. It is known to be absent from both L1 caches, so the remote snoop can be skipped.
- Filter Miss: The address is not found. The system must perform the normal snoop operation.

Example

Consider two private L1 caches:

- L1 Cache 0
- L1 Cache 1

Suppose address "0x1000" is absent from both caches.

The address is inserted into the snoop filter.

When another request queries "0x1000", the filter generates a hit, indicating that the remote snoop operation can be avoided.

However, if the address is not present in the filter, the normal snooping mechanism must be performed.

Important: A filter miss does not necessarily mean that the address exists in a cache. It simply means that the filter cannot guarantee its absence.

4. Architecture

The module uses a fully associative lookup architecture.

Every valid entry is compared simultaneously with the incoming query address.

Internal Components

Component| Function
"addr_mem"| Stores addresses known to be absent from both L1 caches
"valid_mem"| Indicates whether an entry is valid
"hit_comb"| Stores the combinational lookup result
"replace_ptr"| Maintains the round-robin replacement position
"duplicate_found"| Detects an already existing address
"free_found"| Detects whether an invalid entry is available
"free_index"| Stores the first available entry index

Architecture Flow

1. Receive the query address.
2. Compare it with every valid filter entry.
3. Generate "filter_hit".
4. Generate "snoop_required" as the inverse of "filter_hit".
5. Update the filter when insertion, removal, or clearing is requested.

5. Input and Output Signals

Inputs

Signal| Description
"clk"| Clock signal
"rst_n"| Active-low asynchronous reset
"query_addr"| Address being checked
"insert_absent"| Requests insertion of an address known to be absent from both caches
"insert_addr"| Address to be inserted
"remove_addr_valid"| Enables address removal
"remove_addr"| Address to be removed
"clear_all"| Invalidates all filter entries

Outputs

Signal| Description
"filter_hit"| Indicates that the queried address is present in the filter
"snoop_required"| Indicates whether normal snooping is required

6. Detailed Operation

A. Lookup Operation

The lookup is implemented using a combinational "always @*" block.

The module iterates through all filter entries and checks:

- Whether the entry is valid.
- Whether the stored address matches the query address.

If a valid matching entry is found, "hit_comb" becomes HIGH.

The outputs are:

- "filter_hit = hit_comb"
- "snoop_required = ~filter_hit"

B. Insertion Operation

When "insert_absent" is HIGH:

1. The module checks whether the address already exists.
2. If a duplicate is detected, insertion is ignored.
3. Otherwise, the first available invalid entry is selected.
4. The new address is stored.
5. Its corresponding valid bit is set to HIGH.

This prevents duplicate entries and efficiently utilizes available storage.

C. Replacement Operation

When all filter entries are occupied:

- The module replaces an existing entry using round-robin replacement.
- "replace_ptr" identifies the entry to be replaced.
- After replacement, the pointer advances to the next entry.
- When the last entry is reached, the pointer returns to zero.

This ensures that entries are replaced in a cyclic manner.

D. Removal Operation

When "remove_addr_valid" is HIGH:

- All valid entries are checked against "remove_addr".
- Every matching entry is invalidated.
- The address is no longer considered safe for snoop suppression.

Removal is important whenever a cache may acquire or install the corresponding address.

E. Clear Operation

When "clear_all" is HIGH:

- All valid bits are cleared.
- The replacement pointer is reset to zero.
- All previous negative information is discarded.

The stored address bits do not need to be cleared because invalid entries are ignored during lookup.

F. Reset Operation

The module uses an active-low asynchronous reset.

When "rst_n" becomes LOW:

- All valid bits are cleared.
- All address registers are initialized to zero.
- The replacement pointer is initialized to zero.

This ensures that the filter starts in a safe empty state.

7. Update Priority

The module follows the following update priority:

1. Asynchronous Reset
2. "clear_all"
3. "remove_addr_valid"
4. "insert_absent"
5. Hold Previous State

If removal and insertion are requested simultaneously, removal takes priority.

This prevents an address from being reinserted in the same cycle in which it is being invalidated.

8. Parameterization

The module supports two configurable parameters.

Parameter| Default Value| Description
"ADDR_WIDTH"| 16| Width of the memory address
"FILTER_ENTRIES"| 4| Number of entries in the filter

For example, with the default configuration:

- Address width = 16 bits.
- Filter capacity = 4 entries.
- Total address storage = 64 bits.
- Valid bits = 4 bits.

Zero-Entry Bypass Mode

When "FILTER_ENTRIES = 0", the module operates in bypass mode.

In this mode:

- "filter_hit" is always LOW.
- "snoop_required" is always HIGH.
- No filter storage or lookup logic is used.

Therefore, the system always performs normal snooping.

9. Example of Filter Operation

Consider a filter with four entries.

Entry| Address| Valid
0| 0x1000| 1
1| 0x2000| 1
2| 0x0000| 0
3| 0x0000| 0

Case 1: Query = 0x1000

- Address is found in entry 0.
- "filter_hit = 1"
- "snoop_required = 0"

Case 2: Query = 0x3000

- Address is not found.
- "filter_hit = 0"
- "snoop_required = 1"

Case 3: Remove address = 0x1000

- Entry 0 is invalidated.
- A subsequent query for 0x1000 generates a filter miss.

10. Advantages

- Reduces unnecessary snoop transactions.
- Uses a simple fully associative lookup architecture.
- Supports dynamic insertion and removal.
- Prevents duplicate entries.
- Uses round-robin replacement when the filter is full.
- Supports configurable address width and filter capacity.
- Provides a safe bypass mode when filtering is disabled.

11. Limitations

- The fully associative lookup requires parallel address comparisons.
- Hardware complexity increases with the number of filter entries.
- The filter does not maintain cache ownership or modified-state information.
- Correctness depends on proper integration with the cache controllers.
- A filter eviction can increase snoop traffic because negative information is lost.

12. Integration Requirements

The filter must be integrated carefully with both L1 cache controllers.

The following rules must be maintained:

1. Remove an address before any cache can acquire or install it.
2. Insert an address only after both caches are confirmed absent.
3. Ensure no pending cache fill or ownership grant exists when inserting.
4. On a filter miss, execute the normal snooping mechanism.
5. On a filter hit, skip the remote snoop only when the negative-information invariant is guaranteed.

These conditions are essential for maintaining cache coherence.

13. Conclusion

The Exclusive Negative Snoop Filter provides a mechanism for reducing unnecessary snoop transactions in a two-cache coherent system.

By tracking addresses known to be absent from both private L1 caches, the module allows the system to bypass remote snooping when it is safe to do so.

The design uses fully associative lookup, duplicate detection, dynamic insertion and removal, and round-robin replacement.

It is implemented using synthesizable Verilog HDL and can be extended to support larger filter capacities and more complex cache coherence architectures.

14. Technologies Used

- Hardware Description Language: Verilog HDL
- Design Approach: RTL Design
- Architecture: Fully Associative Negative Snoop Filter
- Simulation: Verilog HDL Simulator
- Application: Cache Coherence Optimization
