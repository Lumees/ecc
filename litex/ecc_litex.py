# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
ECC LiteX Module
==================
Directly instantiates ecc_top.sv and wires it to LiteX CSR registers.

CSR registers:
  ctrl        [0]=enc_start(self-clearing) [1]=dec_start(self-clearing)
  status      [0]=enc_done(RO) [1]=dec_done(RO) [3:2]=dec_status(RO)
  enc_data    Data input for encoding [DATA_W-1:0]
  enc_code_lo Encoded codeword bits [31:0] (RO)
  enc_code_hi Encoded codeword bits [CODE_W-1:32] (RO, for CODE_W>32)
  dec_code_lo Codeword for decoding bits [31:0]
  dec_code_hi Codeword for decoding bits [CODE_W-1:32]
  dec_data    Decoded data [DATA_W-1:0] (RO)
  dec_syndrome Syndrome [PARITY_W-1:0] (RO)
  info        [7:0]=DATA_W [15:8]=CODE_W [23:16]=PARITY_W (RO)
  version     IP version (RO)
"""

from migen import *
from litex.soc.interconnect.csr import *

import os

ECC_RTL_DIR = os.path.join(os.path.dirname(__file__), '../rtl')


class ECC(Module, AutoCSR):
    def __init__(self, platform, data_w=32):
        # ── Compute parameters (must match ecc_pkg.sv) ────────────────────
        m = 1
        while (1 << m) < (data_w + m + 1):
            m += 1
        parity_w = m
        check_w  = parity_w + 1
        code_w   = data_w + check_w

        # ── Platform sources ──────────────────────────────────────────────
        for f in ['ecc_pkg.sv', 'ecc_core.sv', 'ecc_top.sv']:
            platform.add_source(os.path.join(ECC_RTL_DIR, f))

        # ── CSR registers (RW) ────────────────────────────────────────────
        self.ctrl        = CSRStorage(8,  name="ctrl",
                                      description="[0]=enc_start [1]=dec_start (self-clear)")
        self.enc_data    = CSRStorage(32, name="enc_data",
                                      description="Encoder data input")
        self.dec_code_lo = CSRStorage(32, name="dec_code_lo",
                                      description="Decoder codeword input [31:0]")
        self.dec_code_hi = CSRStorage(32, name="dec_code_hi",
                                      description="Decoder codeword input [CODE_W-1:32]")

        # ── CSR registers (RO) ────────────────────────────────────────────
        self.status      = CSRStatus(8,  name="status",
                                     description="[0]=enc_done [1]=dec_done [3:2]=dec_status")
        self.enc_code_lo = CSRStatus(32, name="enc_code_lo",
                                     description="Encoded codeword [31:0]")
        self.enc_code_hi = CSRStatus(32, name="enc_code_hi",
                                     description="Encoded codeword [CODE_W-1:32]")
        self.dec_data    = CSRStatus(32, name="dec_data",
                                     description="Decoded data")
        self.dec_syndrome = CSRStatus(32, name="dec_syndrome",
                                      description="Decoder syndrome")
        self.info        = CSRStatus(32, name="info",
                                     description="[7:0]=DATA_W [15:8]=CODE_W [23:16]=PARITY_W")
        self.version     = CSRStatus(32, name="version",
                                     description="IP version")

        # ── Constant outputs ──────────────────────────────────────────────
        self.comb += [
            self.info.status.eq((parity_w << 16) | (code_w << 8) | data_w),
        ]

        # ── Core signals ──────────────────────────────────────────────────
        enc_valid_i    = Signal()
        dec_valid_i    = Signal()
        enc_valid_o    = Signal()
        enc_code_o     = Signal(code_w)
        dec_valid_o    = Signal()
        dec_data_o     = Signal(data_w)
        dec_status_o   = Signal(2)
        dec_syndrome_o = Signal(parity_w)
        version_sig    = Signal(32)

        # Start pulses: fire when ctrl register is written
        self.comb += [
            enc_valid_i.eq(self.ctrl.re & self.ctrl.storage[0]),
            dec_valid_i.eq(self.ctrl.re & self.ctrl.storage[1]),
        ]

        # Latch encode results
        enc_done    = Signal()
        enc_code_lat = Signal(code_w)
        self.sync += [
            If(enc_valid_i, enc_done.eq(0)),
            If(enc_valid_o,
                enc_done.eq(1),
                enc_code_lat.eq(enc_code_o),
            ),
        ]
        self.comb += [
            self.enc_code_lo.status.eq(enc_code_lat[:32]),
        ]
        if code_w > 32:
            self.comb += self.enc_code_hi.status.eq(enc_code_lat[32:code_w])
        else:
            self.comb += self.enc_code_hi.status.eq(0)

        # Latch decode results
        dec_done     = Signal()
        dec_data_lat = Signal(data_w)
        dec_stat_lat = Signal(2)
        dec_synd_lat = Signal(parity_w)
        self.sync += [
            If(dec_valid_i, dec_done.eq(0)),
            If(dec_valid_o,
                dec_done.eq(1),
                dec_data_lat.eq(dec_data_o),
                dec_stat_lat.eq(dec_status_o),
                dec_synd_lat.eq(dec_syndrome_o),
            ),
        ]
        self.comb += [
            self.dec_data.status.eq(dec_data_lat),
            self.dec_syndrome.status.eq(dec_synd_lat),
        ]

        # Status register
        self.comb += [
            self.status.status[0].eq(enc_done),
            self.status.status[1].eq(dec_done),
            self.status.status[2].eq(dec_stat_lat[0]),
            self.status.status[3].eq(dec_stat_lat[1]),
        ]

        # IRQ on done
        self.irq = Signal()
        enc_done_prev = Signal()
        dec_done_prev = Signal()
        self.sync += [
            enc_done_prev.eq(enc_done),
            dec_done_prev.eq(dec_done),
        ]
        self.comb += self.irq.eq(
            (enc_done & ~enc_done_prev) | (dec_done & ~dec_done_prev)
        )

        # ── Build decoder codeword from two CSR registers ────────────────
        dec_code_full = Signal(code_w)
        if code_w > 32:
            self.comb += dec_code_full.eq(
                Cat(self.dec_code_lo.storage[:32],
                    self.dec_code_hi.storage[:code_w - 32])
            )
        else:
            self.comb += dec_code_full.eq(self.dec_code_lo.storage[:code_w])

        # ── ECC top instance ──────────────────────────────────────────────
        self.specials += Instance("ecc_top",
            i_clk            = ClockSignal(),
            i_rst_n          = ~ResetSignal(),
            i_enc_valid_i    = enc_valid_i,
            i_enc_data_i     = self.enc_data.storage[:data_w],
            o_enc_valid_o    = enc_valid_o,
            o_enc_code_o     = enc_code_o,
            i_dec_valid_i    = dec_valid_i,
            i_dec_code_i     = dec_code_full,
            o_dec_valid_o    = dec_valid_o,
            o_dec_data_o     = dec_data_o,
            o_dec_status_o   = dec_status_o,
            o_dec_syndrome_o = dec_syndrome_o,
            o_version_o      = version_sig,
        )

        self.comb += self.version.status.eq(version_sig)
