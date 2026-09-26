// functions.sv - three pairs of Boolean functions for SAT-based equivalence checking (equivalence/check.sh).

// Y0 = (A + B)(C' + D)(A + C')          Y1 = AC' + AD + C'D + A'BD'
module y0 (input logic a, b, c, d, output logic y); assign y = (a | b) & (~c | d) & (a | ~c);                    endmodule
module y1 (input logic a, b, c, d, output logic y); assign y = (a & ~c) | (a & d) | (~c & d) | (~a & b & ~d);    endmodule

// Z0 = B'(A + C)(A' + C')               Z1 = AB'C' + A'B'C
module z0 (input logic a, b, c, output logic y);    assign y = ~b & (a | c) & (~a | ~c);                          endmodule
module z1 (input logic a, b, c, output logic y);    assign y = (a & ~b & ~c) | (~a & ~b & c);                     endmodule

// F0 = (A xor B) xnor C                 F1 = (A'B + AB')C + (AB + A'B')C'
module f0 (input logic a, b, c, output logic y);    assign y = ~((a ^ b) ^ c);                                    endmodule
module f1 (input logic a, b, c, output logic y);    assign y = ((~a & b) | (a & ~b)) & c | ((a & b) | (~a & ~b)) & ~c; endmodule
