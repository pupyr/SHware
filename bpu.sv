

module bpu
(
  input  logic                                     clk,
  input  logic                                     rst_n,

  input  logic                                     bpu_req_i,
  input  logic [PC     			     -1:0] bpu_addr_i,

  input  logic                                     bpu_flush_i,

  output logic                                        bpu_b1_val_o,
  output logic                                        bpu_b2_val_o,
  output logic                                        bpu_b3_val_o,
  output logic					      bpu_b4_val_o,
  output logic                                        bpu_b4_pred_val_o,

  output logic [TAGE_IND                        -1:0] bpu_b3_tage_index_o,

  input  logic                                     bpu_update_i,
  input  logic [TAGE_IND                     -1:0] bpu_tage_ind_i,
  input  logic                                     bpu_taken_i,
  input  logic [PC			     -1:0] bpu_pc_i
);

int fd_tage, fd_result, fd_bim, fd_entrop;

initial fd_tage = $fopen("tage","w");
initial fd_result = $fopen("result","w");
initial fd_bim = $fopen("bim","w");
initial fd_entrop = $fopen("entrop","w");

localparam PART = 14;
localparam INDEX_PHR_PART = PART;
localparam INDEX_GHR_PART = PART;
localparam INDEX_ADDR_PART = PART;
localparam PHR_SIZE = 2**INDEX_PHR_PART;
localparam MEM_ADDR = PART;
localparam MEM_SIZE = 2**MEM_ADDR;
localparam TAGE_NUM = 12;
localparam TAGE_U_AGE = 2;
localparam TAGE_ADDR = PART;
localparam TAGE_TAB_SIZE = 2**PART;

int time_g;

logic b1,b2,b3,b4;
logic direction_b4;
logic [PC     	 -1:0] b1_addr,b2_addr,b3_addr,b4_addr;
logic [TAGE_IND  -1:0] bpu_tage_ind_ff, bpu_tage_ind_ff_2;

logic [1:0] mem [MEM_SIZE];
logic [INDEX_GHR_PART-1:0] ghr;
logic [INDEX_PHR_PART-1:0] phr [PHR_SIZE];
logic [MEM_SIZE-1:0] entrop;
logic addresses [longint];
int entrop_counter = 0;
int addresses_counter = 0;

logic [PC     -1:0] addr, addr_coach, addr_coach_ff;
logic [PC     -1:0] addr_b1, addr_b2;
logic [PC     -1:0] addr_tag, addr_tag_coach, addr_tag_coach_ff;
logic [INDEX_GHR_PART-1:0] buf_ghr [$];
logic [INDEX_GHR_PART-1:0] buf_ghr_head;
logic [INDEX_PHR_PART-1:0] buf_phr [$];
logic [INDEX_PHR_PART-1:0] buf_phr_head;
logic [INDEX_PHR_PART-1:0] phr_cur, coach_phr;

logic bpu_update_ff, bpu_update_ff_2;
logic bpu_taken_ff, bpu_taken_ff_2;
logic [PC     -1:0] bpu_addr_ff, bpu_addr_ff_2;
logic [PC     -1:0] bpu_pc_ff, bpu_pc_ff_2;
logic bpu_flush_ff, bpu_flush_ff_2;


initial time_g = 0;

always @(posedge clk, negedge rst_n) begin
  time_g++;
  if (!rst_n) begin
    b1 <= 0;
    b2 <= 0;
    b3 <= 0;
    b4 <= 0;

    b1_addr <= 0;
    b2_addr <= 0;
    b3_addr <= 0;
    b4_addr <= 0;

    ghr <= '0;
    
    entrop <= {MEM_SIZE{0}};

    for(int i=0; i<PHR_SIZE; i++) phr[i] <= '0;
    for(int i=0; i<MEM_SIZE; i++) mem[i] <= '0;

    bpu_update_ff <= 0;
    bpu_update_ff_2 <= 0;
    bpu_taken_ff <= 0;
    bpu_taken_ff_2 <= 0;
    bpu_pc_ff <= 0;
    bpu_pc_ff_2 <= 0;
    bpu_flush_ff <= 0;
    bpu_flush_ff_2 <= 0;
    bpu_tage_ind_ff <= 0;
    bpu_tage_ind_ff_2 <= 0;
    bpu_addr_ff <= 0;
    bpu_addr_ff_2 <= 0;

  end else begin
    b2 <= b1;
    b3 <= b2;
    b4 <= b3;

    b2_addr <= b1_addr;
    b3_addr <= b2_addr;
    b4_addr <= b3_addr;

    bpu_update_ff <= bpu_update_i;
    bpu_update_ff_2 <= bpu_update_ff;
    bpu_taken_ff <= bpu_taken_i;
    bpu_taken_ff_2 <= bpu_taken_ff;
    bpu_pc_ff <= bpu_pc_i;
    bpu_pc_ff_2 <= bpu_pc_ff;
    bpu_flush_ff <= bpu_flush_i;
    bpu_flush_ff_2 <= bpu_flush_ff;
    bpu_tage_ind_ff <= bpu_tage_ind_i;
    bpu_tage_ind_ff_2 <= bpu_tage_ind_ff;
    bpu_addr_ff <= bpu_addr_i;
    bpu_addr_ff_2 <= bpu_addr_ff;

  end
end

task saturation_inc (int i);
  if (mem[i]<2'b11) mem[i]++;
endtask

task saturation_dec (int i);
  if (mem[i]>2'b00) mem[i]--;
endtask


always @(posedge clk) begin
  if (bpu_req_i) begin
    b1 <= 1;
    b1_addr <= addr;
    buf_ghr.push_back(ghr);
    buf_phr.push_back(phr_cur);
  end
  else begin
    b1 <= 0;
  end
end

always @(posedge clk) begin
  buf_ghr_head = buf_ghr[0];
  buf_phr_head = buf_phr[0];
  if(bpu_update_i) begin
    buf_ghr.pop_front();
    buf_phr.pop_front();
  end
end

assign phr_cur = phr[$unsigned(INDEX_PHR_PART'(bpu_addr_i))];
assign coach_phr = phr[$unsigned(INDEX_PHR_PART'(bpu_pc_i))];

assign addr = $unsigned(INDEX_ADDR_PART'(bpu_addr_i))
                ^($unsigned(INDEX_GHR_PART'(ghr)))
                ^ $unsigned(INDEX_PHR_PART'(phr_cur));

assign addr_tag = addr;


assign addr_coach = $unsigned(INDEX_ADDR_PART'(bpu_pc_i))
                  ^($unsigned(INDEX_GHR_PART'(buf_ghr_head)))
                  ^ $unsigned(INDEX_PHR_PART'(buf_phr_head));

assign addr_tag_coach = addr_coach;

always @(posedge clk) begin
  if (bpu_update_i) begin
    $fwrite(fd_entrop, "%d:%h %h %d %d %b\n", time_g, bpu_pc_i, addr_coach, entrop_counter, addresses_counter,
      (entrop[addr_coach] != 0 && !addresses.exists(bpu_pc_i)));
    if(entrop[addr_coach] == 0) entrop_counter++;
    entrop[addr_coach] <= 1;
    if(!addresses.exists(bpu_pc_i)) begin
      addresses_counter++;
    end
    addresses[bpu_pc_i] = 1;

    if (bpu_taken_i) saturation_inc(addr_coach);
    else saturation_dec(addr_coach);

    ghr <= {bpu_taken_i, ghr[INDEX_GHR_PART-1:1]};
    phr[$unsigned(INDEX_PHR_PART'(bpu_pc_i))] <= {bpu_taken_i, coach_phr[INDEX_PHR_PART-1:1]};
  end
end


logic [TAGE_NUM-1:0] hit;
logic [TAGE_U_AGE-1:0] u_match [TAGE_NUM];
logic [1:0] bi_match [TAGE_NUM];
logic [1:0] bi [TAGE_NUM];

logic [1:0] bimodal_0 [TAGE_TAB_SIZE];
logic [TAGE_U_AGE-1:0] u_0 [TAGE_TAB_SIZE];

logic [TAGE_NUM-1:0] misspred;

assign hit[0] = 1;
assign u_match[0] = u_0[TAGE_ADDR'(addr)];
assign bi[0] = bimodal_0[TAGE_ADDR'(addr_b1)];

int index, index_ff;

int ret_index;


always @(posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    ret_index         <= 0;
    index_ff          <= 0;
    addr_b1           <= 0;
    addr_b2           <= 0;
    addr_coach_ff     <= 0;
    addr_tag_coach_ff <= 0;
    for(int i=0; i<TAGE_TAB_SIZE; i++) begin
      u_0[i] <= 1;
      bimodal_0[i] <= '0;
    end
  end else begin
    index_ff <= index;
    ret_index <= bpu_tage_ind_i;

    addr_b1 <= addr;
    addr_b2 <= addr_b1;

    addr_coach_ff     <= addr_coach;
    addr_tag_coach_ff <= addr_tag_coach;

    if (bpu_req_i) bi_match[0] <= bimodal_0[TAGE_ADDR'(addr)];

    if (bpu_update_i) begin
      if(bpu_taken_i) bimodal_0[TAGE_ADDR'(addr_coach)] <= bimodal_0[TAGE_ADDR'(addr_coach)] < 3 ? bimodal_0[TAGE_ADDR'(addr_coach)] + 1 : bimodal_0[TAGE_ADDR'(addr_coach)];
      else                        bimodal_0[TAGE_ADDR'(addr_coach)] <= bimodal_0[TAGE_ADDR'(addr_coach)] > 0 ? bimodal_0[TAGE_ADDR'(addr_coach)] - 1 : bimodal_0[TAGE_ADDR'(addr_coach)];


      $fwrite(fd_bim, "ret %d:addr_coach %h addr_coach_sliced %h tkn %b ghr %b phr %b\n", 
        time_g, 
        addr_coach, 
        $unsigned(INDEX_ADDR_PART'(addr_coach)), 
        bpu_taken_i,
        buf_ghr_head,
        buf_phr_head);

      if (bpu_taken_i == bimodal_0[TAGE_ADDR'(addr_coach)][1]) begin
        misspred[0] <= 0;
      end else begin
        misspred[0] <= 1;
      end
    end

    if (bpu_update_ff) begin
      u_0[TAGE_ADDR'(addr_coach_ff)] <= !misspred[0]
                                      ? u_0[TAGE_ADDR'(addr_coach_ff)]!=2'b11
                                        ? u_0[TAGE_ADDR'(addr_coach_ff)] + 1
                                        : u_0[TAGE_ADDR'(addr_coach_ff)]
                                      : u_0[TAGE_ADDR'(addr_coach_ff)]!=0 
                                        ? u_0[TAGE_ADDR'(addr_coach_ff)] - 1
                                        : u_0[TAGE_ADDR'(addr_coach_ff)];

    end
  end
end

for(genvar i = 1; i<TAGE_NUM; i++) begin: gen_tage

  localparam val = i;
  logic [val-1       :0]  tag     [TAGE_TAB_SIZE];
  logic [1           :0]  bimodal [TAGE_TAB_SIZE];
  logic [TAGE_U_AGE-1:0]  u       [TAGE_TAB_SIZE];

  logic ret_hit;

  assign bi[i] = bimodal[TAGE_ADDR'(addr_coach_ff)];

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      ret_hit <= 0;
      misspred[i] = 0;
      hit[i] <= 0;
      for (int j=0; j<TAGE_TAB_SIZE; j++) begin
        u[j] <= 0;
        bimodal[j] <= '0;
      end
    end else begin

      if (bpu_update_i) begin
        if (u[TAGE_ADDR'(addr_coach)]>0 && tag[val'(addr_coach)] == val'(addr_tag_coach)) begin
          ret_hit <= 1;
          if(bpu_taken_i) bimodal[TAGE_ADDR'(addr_coach)] <= bimodal[TAGE_ADDR'(addr_coach)] < 3 ? bimodal[TAGE_ADDR'(addr_coach)] + 1 : bimodal[TAGE_ADDR'(addr_coach)];
          else                        bimodal[TAGE_ADDR'(addr_coach)] <= bimodal[TAGE_ADDR'(addr_coach)] > 0 ? bimodal[TAGE_ADDR'(addr_coach)] - 1 : bimodal[TAGE_ADDR'(addr_coach)];
          if (bpu_taken_i == bimodal[TAGE_ADDR'(addr_coach)][1]) begin
            misspred[i] <= 0;
          end else begin
            misspred[i] <= 1;
          end
        end
        else begin
          ret_hit <= 0;
        end
      end

      if (bpu_update_ff) begin
        if(misspred[ret_index] && u[TAGE_ADDR'(addr_coach_ff)]==0) begin
          tag [val'(addr_coach_ff)] <= addr_tag_coach_ff;
          bimodal [TAGE_ADDR'(addr_coach_ff)] <= bi[ret_index];
          u[TAGE_ADDR'(addr_coach_ff)] <= 2;
        end
        if (ret_hit)
          u[TAGE_ADDR'(addr_coach_ff)] <= !misspred[i]
                                ? u[TAGE_ADDR'(addr_coach_ff)]!=2'b11
                                  ? u[TAGE_ADDR'(addr_coach_ff)] + 1
                                  : u[TAGE_ADDR'(addr_coach_ff)]
                                : u[TAGE_ADDR'(addr_coach_ff)]!=0 
                                  ? u[TAGE_ADDR'(addr_coach_ff)] - 1
                                  : u[TAGE_ADDR'(addr_coach_ff)];
      end

      if (bpu_req_i) begin
        if(tag[val'(addr)] == val'(addr_tag) && u[TAGE_ADDR'(addr)]!=0) begin
          hit[i]      <= 1;
          u_match [i] <= u       [TAGE_ADDR'(addr)];
          bi_match[i] <= bimodal [TAGE_ADDR'(addr)];
        end
        else hit[i] <= 0;
      end
    end
  end

end: gen_tage

logic [TAGE_U_AGE-1:0] u_hit_max;

string u_str, u_temp;

always @(posedge clk) begin
  if (b2) begin
    $fwrite(fd_tage,"%d: addr: 0x%h table_index: %2d counter: %b ghr: %b phr: %b\n", 
      time_g, 
      addr_b2, 
      index, 
      bi_match[index],
      ghr,
      phr[INDEX_PHR_PART'(bpu_addr_ff_2)]);
  end
  if (bpu_update_ff_2) begin
    u_str = "";
    for (int i=TAGE_NUM-1; i>=0; i--) begin
      if(hit[i]) begin
        u_temp.itoa(u_match[i]);
        u_str = {u_str, " ", u_temp};
      end
      else u_str = {u_str, " ?"};
    end
    $fwrite(fd_result, "%d: addr: 0x%h tn: %b mispred: %b index:%d hit: %b u: %s\n", 
      time_g,
      bpu_pc_ff_2, 
      bpu_taken_ff_2, 
      bpu_flush_ff_2, 
      bpu_tage_ind_ff_2,
      hit,
      u_str);
  end
  if (b1) begin 
    u_hit_max = 0;
    for(int i=0; i<TAGE_NUM; i++) begin
      if(hit[i] && u_match[i]>=u_hit_max) begin
        u_hit_max = u_match[i];
        index = i;
      end
    end
  end
end

always @(posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    direction_b4 <= 0;
  end else begin
    // direction_b4 <= bi_match[index_ff][1]; // in case of tage test
    if (b3) begin
      $fwrite(fd_bim, "bpu %d:%h %h %b\n", time_g, b3_addr, $unsigned(INDEX_ADDR_PART'(b3_addr)), mem[$unsigned(INDEX_ADDR_PART'(b3_addr))]);
    end
    direction_b4 <= (mem[$unsigned(INDEX_ADDR_PART'(b3_addr))][1]);
  end
end

assign bpu_b1_val_o = b1;
assign bpu_b2_val_o = b2;
assign bpu_b3_val_o = b3;
assign bpu_b4_val_o = b4;

assign bpu_b4_pred_taken_o = direction_b4;
assign bpu_b3_tage_index_o = index_ff;

endmodule : bpu
