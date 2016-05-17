// ZX Spectrum for Altera DE1
//
// Copyright (c) 2009-2011 Mike Stirling
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without 
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

// PS/2 scancode to Spectrum matrix conversion
module keyboard
(
	input             reset,
	input             clk_sys,

	input             ps2_kbd_clk,
	input             ps2_kbd_data,

	input      [15:0] addr,
	output      [7:0] key_data,

	output reg [11:1] Fn = 0,
	output reg  [2:0] mod = 0
);

reg  [3:0] prev_clk  = 0;
reg [11:0] shift_reg = 12'hFFF;
wire[11:0] kdata = {ps2_kbd_data,shift_reg[11:1]};
wire [7:0] kcode = kdata[9:2];
reg  [7:0] keys[8:0];
reg        release_btn = 0;

// Output addressed row to ULA
assign key_data = (!addr[8]    ? keys[0] : 8'hFF)
                 &(!addr[9]    ? keys[1] : 8'hFF)
                 &(!addr[10]   ? keys[2] : 8'hFF)
                 &(!addr[11]   ? keys[3] : 8'hFF)
                 &(!addr[12]   ? keys[4] : 8'hFF)
                 &(!addr[13]   ? keys[5] : 8'hFF)
                 &(!addr[14]   ? keys[6] : 8'hFF)
                 &(!addr[15]   ? keys[7] : 8'hFF)
                 &(&addr[15:8] ? keys[8] : 8'hFF);

wire shift = mod[0];
always @(posedge clk_sys) begin
	reg old_reset = 0;
	old_reset <= reset;

	if(~old_reset & reset)begin
		prev_clk  <= 0;
		shift_reg <= 12'hFFF;
		keys[0] <= 'hFF;
		keys[1] <= 'hFF;
		keys[2] <= 'hFF;
		keys[3] <= 'hFF;
		keys[4] <= 'hFF;
		keys[5] <= 'hFF;
		keys[6] <= 'hFF;
		keys[7] <= 'hFF;
		keys[8] <= 'hFF;
	end else begin
		prev_clk <= {ps2_kbd_clk,prev_clk[3:1]};
		if(prev_clk == 1) begin
			if (kdata[11] & ^kdata[10:2] & ~kdata[1] & kdata[0]) begin
				shift_reg <= 12'hFFF;

				if (kcode == 8'he0) ;
				// Extended key code follows
				else if (kcode == 8'hf0)
					// Release code follows
					release_btn <= 1;
				else begin
					// Cancel extended/release flags for next time
					release_btn <= 0;

					case(kcode)
						8'h59: mod[0]<= ~release_btn; // right shift
						8'h11: mod[1]<= ~release_btn; // alt
						8'h14: mod[2]<= ~release_btn; // ctrl
						8'h05: Fn[1] <= ~release_btn; // F1
						8'h06: Fn[2] <= ~release_btn; // F2
						8'h04: Fn[3] <= ~release_btn; // F3
						8'h0C: Fn[4] <= ~release_btn; // F4
						8'h03: Fn[5] <= ~release_btn; // F5
						8'h0B: Fn[6] <= ~release_btn; // F6
						8'h83: Fn[7] <= ~release_btn; // F7
						8'h0A: Fn[8] <= ~release_btn; // F8
						8'h01: Fn[9] <= ~release_btn; // F9
						8'h09: Fn[10]<= ~release_btn; // F10
						8'h78: Fn[11]<= ~release_btn; // F11
					endcase

					case(kcode)
						8'h12 : keys[0][0] <= release_btn; // Left shift (CAPS SHIFT)
						8'h1a : keys[0][1] <= release_btn; // Z
						8'h22 : keys[0][2] <= release_btn; // X
						8'h21 : keys[0][3] <= release_btn; // C
						8'h2a : keys[0][4] <= release_btn; // V
						8'h05 : keys[0][5] <= release_btn; // F1
						8'h06 : keys[0][6] <= release_btn; // F2
						8'h04 : keys[0][7] <= release_btn; // F3

						8'h1c : keys[1][0] <= release_btn; // A
						8'h1b : keys[1][1] <= release_btn; // S
						8'h23 : keys[1][2] <= release_btn; // D
						8'h2b : keys[1][3] <= release_btn; // F
						8'h34 : keys[1][4] <= release_btn; // G
						8'h0C : keys[1][5] <= release_btn; // F4
						8'h03 : keys[1][6] <= release_btn; // F5
						8'h0B : keys[1][7] <= release_btn; // F6

						8'h15 : keys[2][0] <= release_btn; // Q
						8'h1d : keys[2][1] <= release_btn; // W
						8'h24 : keys[2][2] <= release_btn; // E
						8'h2d : keys[2][3] <= release_btn; // R
						8'h2c : keys[2][4] <= release_btn; // T
						8'h83 : keys[2][5] <= release_btn; // F7
						8'h0A : keys[2][6] <= release_btn; // F8
						8'h01 : keys[2][7] <= release_btn; // F9

						8'h16 : keys[3][0] <= release_btn; // 1
						8'h1e : keys[3][1] <= release_btn; // 2
						8'h26 : keys[3][2] <= release_btn; // 3
						8'h25 : keys[3][3] <= release_btn; // 4
						8'h2e : keys[3][4] <= release_btn; // 5
						8'h76 : keys[3][5] <= release_btn; // Escape
						8'h0D : keys[3][6] <= release_btn; // TAB
						8'h58 : keys[3][7] <= release_btn; // Caps lock

						8'h45 : keys[4][0] <= release_btn; // 0
						8'h46 : keys[4][1] <= release_btn; // 9
						8'h3e : keys[4][2] <= release_btn; // 8
						8'h3d : keys[4][3] <= release_btn; // 7
						8'h36 : keys[4][4] <= release_btn; // 6
						8'h4E : keys[4][5] <= release_btn; // -
						8'h55 : keys[4][6] <= release_btn; // +
						8'h66 : keys[4][7] <= release_btn; // Backspace (DEL)

						8'h4d : keys[5][0] <= release_btn; // P
						8'h44 : keys[5][1] <= release_btn; // O
						8'h43 : keys[5][2] <= release_btn; // I
						8'h3c : keys[5][3] <= release_btn; // U
						8'h35 : keys[5][4] <= release_btn; // Y
						8'h0E : keys[5][5] <= release_btn; // `
						8'h52 : keys[5][6] <= release_btn; // "
						8'h09 : keys[5][7] <= release_btn; // F10 (F0)

						8'h5a : keys[6][0] <= release_btn; // ENTER
						8'h4b : keys[6][1] <= release_btn; // L
						8'h42 : keys[6][2] <= release_btn; // K
						8'h3b : keys[6][3] <= release_btn; // J
						8'h33 : keys[6][4] <= release_btn; // H
						8'h4C : begin
								if(release_btn) keys[6][6:5] <= 2'b11; // ; :
								else begin
									if(shift) keys[6][6] <= 0;
										else keys[6][5] <= 0;
								end
							end
						8'h1F : keys[6][7] <= release_btn; // LGUI (EDIT)

						8'h29 : keys[7][0] <= release_btn; // SPACE
						8'h11 : keys[7][1] <= release_btn; // Alt (Symbol Shift)
						8'h3a : keys[7][2] <= release_btn; // M
						8'h31 : keys[7][3] <= release_btn; // N
						8'h32 : keys[7][4] <= release_btn; // B
						8'h41 : keys[7][5] <= release_btn; // ,
						8'h49 : keys[7][6] <= release_btn; // .
						8'h5D : keys[7][7] <= release_btn; // \

						8'h14 : keys[8][0] <= release_btn; // Ctrl
						8'h75 : keys[8][1] <= release_btn; // Up
						8'h72 : keys[8][2] <= release_btn; // Down
						8'h6B : keys[8][3] <= release_btn; // Left
						8'h74 : keys[8][4] <= release_btn; // Right

						//8'h4A :  // / ?
						//8'h54 :  // (
						//8'h5B :  // )
						default: ;
					endcase
				end
			end else begin
				shift_reg <= kdata;
			end
		end
	end	
end
endmodule
