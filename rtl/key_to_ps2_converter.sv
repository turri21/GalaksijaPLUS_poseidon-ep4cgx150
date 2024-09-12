module key_to_ps2_converter (
    input         clk,            // Clock signal
    input  [7:0]  key_code,       // Input: Key scan code
    input         key_pressed,    // Input: Key pressed state
    input         key_strobe,     // Input: New key event indicator
    output reg [10:0] ps2_key     // Output: PS/2 key state
);

reg last_key_strobe = 0; // Register to store the previous key strobe state

always @(posedge clk) begin
    // Check if a new key event is detected
    if (key_strobe != last_key_strobe) begin
        // A new key event occurred; construct ps2_key accordingly
        ps2_key[7:0] <= key_code;        // Assign key scan code
        ps2_key[9]   <= key_pressed;     // Assign pressed/released state
        
        // Toggle the state change indicator (bit 10)
        ps2_key[10]  <= ~ps2_key[10];    // Toggle bit 10 for each new event

        // Handle extended key indicator if needed (bit 8)
        // Set to 1 if the key_code represents an extended key; otherwise, 0.
        ps2_key[8]   <= (key_code == 8'hE0); // Example: Assume 0xE0 is the extended key prefix
        
        last_key_strobe <= key_strobe;  // Update last key strobe state
    end
end

endmodule
