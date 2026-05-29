/**
 * ------------------------------------------------------------
 * Copyright (c) All rights reserved
 * SiLab, Institute of Physics, University of Bonn
 * ------------------------------------------------------------
 *
 * Asymmetric dual-port memory: 2048 x 8-bit (Port A) / 16384 x 1-bit (Port B).
 * Total capacity: 16,384 bits → intended to infer one 7-series RAMB18E1 in
 * block-RAM memory mode. See AMD/Xilinx UG473, 7 Series FPGAs Memory Resources:
 * https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources
 *
 * Replaces the legacy RAMB16_S1_S9 primitive (Spartan-3/Virtex-4 era),
 * which is unsupported in Vivado.
 *
 * Inference strategy:
 *   Underlying array is 2048 × 8-bit. Port A accesses full bytes directly.
 *   Port B maps its 14-bit bit address to byte address ADDRB[13:3] and bit
 *   index ADDRB[2:0]. This keeps the memory declaration in a conventional
 *   byte-wide shape for Vivado inference while preserving the legacy 8-to-1
 *   asymmetric interface.
 *   (* ram_style = "block" *) attribute forces BRAM over distributed RAM.
 *
 * This is deliberately not the dedicated BRAM FIFO mode described in UG473.
 * Although the SPI data path is FIFO-like (bytes are played out serially),
 * spi_core owns the byte/bit addresses, repeat count, waits, and replay control.
 * A BRAM FIFO primitive would hide/destructively advance those pointers, while
 * this block must remain an addressable, replayable SPI pattern/readback memory.
 *
 * Port mapping (unchanged from original):
 *   Port A: 8-bit wide, 2048 deep  — ADDRA[10:0], DINA[7:0], DOUTA[7:0], WEA
 *   Port B: 1-bit wide, 16384 deep — ADDRB[13:0], DINB[0],   DOUTB[0],   WEB
 *
 * Read behaviour: read-first on both ports (consistent with legacy primitive).
 * ------------------------------------------------------------
 */
`ifndef BLK_MEM_GEN_8_TO_1_2K
`define BLK_MEM_GEN_8_TO_1_2K

`timescale 1ns/1ps
`default_nettype none


module blk_mem_gen_8_to_1_2k #(
    // Disable a port's write logic when its write enable is tied low.
    // This avoids elaborating unused cross-clock RAM write paths.
    parameter PORT_A_WRITABLE = 1,
    parameter PORT_B_WRITABLE = 1
) (
    CLKA, CLKB, DOUTA, DOUTB, WEA, WEB, ADDRA, ADDRB, DINA, DINB
);

input  wire         CLKA;
input  wire         CLKB;
output reg  [7 : 0] DOUTA;
output reg  [0 : 0] DOUTB;
input  wire [0 : 0] WEA;
input  wire [0 : 0] WEB;
input  wire [10 : 0] ADDRA;
input  wire [13 : 0] ADDRB;
input  wire [7 : 0] DINA;
input  wire [0 : 0] DINB;

// -------------------------------------------------------------------
// Underlying array: 2048 × 8-bit = 16,384 bits.
// Port B's 14-bit address is split into byte address and bit index.
// -------------------------------------------------------------------

// The generic module supports two writable ports for legacy compatibility, but
// current SPI instances enable only one write port per memory. Verilator cannot
// prove that for the default parameterization and reports MULTIDRIVEN.
// verilator lint_off MULTIDRIVEN
(* ram_style = "block" *)
reg [7:0] ram [0:2047];
// verilator lint_on MULTIDRIVEN

wire [10:0] addrb_word = ADDRB[13:3];
wire [2:0] addrb_bit = ADDRB[2:0];

// ------------------------------
// Port A — 8-bit synchronous read/write or read-only.
// ------------------------------
generate
    if (PORT_A_WRITABLE) begin : port_a_read_write
        always @(posedge CLKA) begin
            DOUTA <= ram[ADDRA];  // read-first: capture old value
            if (WEA)
                ram[ADDRA] <= DINA;
        end
    end else begin : port_a_read_only
        always @(posedge CLKA)
            DOUTA <= ram[ADDRA];
    end
endgenerate

// ------------------------------
// Port B — 1-bit synchronous read/write or read-only.
// ------------------------------
generate
    if (PORT_B_WRITABLE) begin : port_b_read_write
        always @(posedge CLKB) begin
            DOUTB[0] <= ram[addrb_word][addrb_bit];  // read-first: capture old value
            if (WEB)
                ram[addrb_word][addrb_bit] <= DINB[0];
        end
    end else begin : port_b_read_only
        always @(posedge CLKB)
            DOUTB[0] <= ram[addrb_word][addrb_bit];
    end
endgenerate

endmodule

`endif
