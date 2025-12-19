module cs_cipher (
    input  logic        clk,
    input  logic        rst,          
    input  logic        s_axis_tvalid,
    input  logic [63:0] s_axis_tdata,
    output logic        s_axis_tready,
    output logic        m_axis_tvalid,
    output logic [63:0] m_axis_tdata,
    input  logic        m_axis_tready,
    input  logic [127:0] master_key
);

    logic        start_key_gen;
    logic        keys_ready;
    logic [575:0] round_keys;  //k0..k8
    
    key_sh key_gen_inst (
        .clk           (clk),
        .rst           (rst),
        .start_key_gen (start_key_gen),
        .master_key    (master_key),
        .round_keys    (round_keys),
        .keys_ready    (keys_ready)
    );
    
    logic [63:0] k0, k1, k2, k3, k4, k5, k6, k7, k8;
    assign k0 = round_keys[63:0];      
    assign k1 = round_keys[127:64];    
    assign k2 = round_keys[191:128];   
    assign k3 = round_keys[255:192];   
    assign k4 = round_keys[319:256];   
    assign k5 = round_keys[383:320];   
    assign k6 = round_keys[447:384];   
    assign k7 = round_keys[511:448];   
    assign k8 = round_keys[575:512];   
    
    logic [63:0] state_reg;      //текущее состояние шифрования
    logic [2:0]  round_counter;  
    
    logic [63:0] round_out;
    
    logic [63:0] current_key;
    always @(*) begin
        case (round_counter)
            3'd0: current_key = k0;
            3'd1: current_key = k1;
            3'd2: current_key = k2;
            3'd3: current_key = k3;
            3'd4: current_key = k4;
            3'd5: current_key = k5;
            3'd6: current_key = k6;
            3'd7: current_key = k7;
            default: current_key = 64'b0;
        endcase
    end
    
    round round_inst (
        .data_in  (state_reg),
        .subkey   (current_key),
        .data_out (round_out)
    );
    
    typedef enum logic [2:0] {
        IDLE,
        KEY_GEN,
        READY,
        PROCESS_ROUNDS,
        FINAL_XOR,
        OUTPUT
    } state_t;
    
    state_t state, next_state;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            s_axis_tready <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata <= 64'b0;
            state_reg <= 64'b0;
            round_counter <= 3'd0;
            start_key_gen <= 1'b0;
        end else begin
            state <= next_state;
            s_axis_tready <= 1'b0;
            m_axis_tvalid <= 1'b0;

            case (state)
                IDLE: begin
                    start_key_gen <= 1'b1;
                end
                
                KEY_GEN: begin
                    //start_key_gen остается 1 пока не сгенерированы ключи
                    if (keys_ready) begin
                        start_key_gen <= 1'b0;
                    end
                end
                
                READY: begin
                    s_axis_tready <= 1'b1;
                    if (s_axis_tvalid) begin
                        state_reg <= s_axis_tdata;
                        s_axis_tready <= 1'b0;
                        round_counter <= 3'd0;
                    end
                end
                
                PROCESS_ROUNDS: begin
                    state_reg <= round_out;
                    round_counter <= round_counter + 3'd1;
                end
                
                FINAL_XOR: begin
                    state_reg <= state_reg ^ k8;
                end
                
                OUTPUT: begin
                    m_axis_tdata <= state_reg;
                    m_axis_tvalid <= 1'b1;
                end
            endcase
        end
    end

    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                next_state = KEY_GEN;
            end
            
            
            KEY_GEN: begin
                if (keys_ready) next_state = READY;
            end
            
            READY: begin
                if (s_axis_tvalid) next_state = PROCESS_ROUNDS;
            end
            
            PROCESS_ROUNDS: begin
                if (round_counter < 7) begin
                    next_state = PROCESS_ROUNDS;  
                end else if (round_counter == 7) begin
                    next_state = FINAL_XOR;       
                end
            end
            
            FINAL_XOR: begin
                next_state = OUTPUT;
            end
            
            OUTPUT: begin
                if (m_axis_tready ) begin   //&& m_axis_tvalid
                    next_state = READY;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule
