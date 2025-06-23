`define PC 64
`define TAGE_IND 4
`include "tb_drv.sv"


`timescale 1ns/1ns
module tb ();

	logic clk;
	initial begin
		clk = '0;
		forever #(0.5) clk = ~clk;
	end

	logic                                       rst_n;

ret_if ret_iface(clk);
bpu_if bpu_iface(clk);
in_if  in_iface(clk);

bpu inst_bpu
	(
		.clk                              (clk),
		.rst_n                            (rst_n),

		.bpu_req_i              (in_iface.bpu_req_i),
		.bpu_addr_i             (in_iface.bpu_addr_i),
		.bpu_flush_i          	(in_iface.bpu_flush_i),

		.bpu_b1_val_o                 (bpu_iface.b1_val_o),
		.bpu_b2_val_o                 (bpu_iface.b2_val_o),
		.bpu_b3_val_o                 (bpu_iface.b3_val_o),
		.bpu_b4_val_o                 (bpu_iface.b4_val_o),
		.bpu_b4_pred_taken_o          (bpu_iface.b4_pred_taken_o),
        	.bpu_b3_tage_index_o          (bpu_iface.b3_tage_index_o),

		.bpu_update_i                 (ret_iface.update_i),
        	.bpu_tage_ind_i               (ret_iface.tage_ind_i),
		.bpu_taken_i          	      (ret_iface.taken_i),
		.bpu_pc_i             	      (ret_iface.pc_i),
	);


logic [112:0] ghr;
logic [97:0] phr;

task update_hist(logic dir, Block bl);
    ghr = {ghr[111:0], dir};
    phr = {phr[96:0], bl.cfi_address[1]};
endtask


ret_driver drv_ret;
bpu_driver drv_bpu;
in_driver drv_in;

Block blocks [$];

    task load_trace( string path );
        
        int fd;
        Block bl;

        bl = new();
        fd = $fopen(path,"r");
        while (!$feof(fd)) begin
            bl.parse_from_log(fd);
            blocks.push_back(bl.copy());
        end
        $fclose(fd);
    endtask

Block bl_in_q [$];
Block bl_out_q [$];

bpu_t pred_in_q [$];
bpu_t pred_out_q [$];

int cfi_commited = 0;
int cfi_taken    = 0;
int cfi_not_taken = 0;

int predicted_taken = 0;
int predicted_not_taken = 0;
int predicted = 0;
int misp_dir = 0;

task print_statistics();
    real prd, mis_pred;
    prd  = real'(predicted);
    mis_pred = real'(predicted + misp_dir);
    $display("");
    $display("cfi_commited  %d vs %d", cfi_commited, cfi_taken + cfi_not_taken);                 
    $display("cfi_taken     %d", cfi_taken);             
    $display("cfi_not_taken %d", cfi_not_taken);                 
    $display("predicted     %d", predicted);
    $display("predicted_t   %d", predicted_taken);
    $display("predicted_nt  %d", predicted_not_taken);            
    $display("misp_dir      %d", misp_dir);             
    $display("all           %d", predicted + misp_dir);
    $display("acuracy       %f", prd * 100 / mis_pred);
endtask

int tage_trace_fd;
int fd_out;

task flush(logic [PC -1:0] addr, logic req);
    if (req) begin
        drv_in.send_ret_flush();
        @(posedge clk);
        drv_bpu.flush();
        drv_in.send_addr(addr);
        @(posedge clk);
        pred_in_q.delete();
        pred_out_q.delete();
    end
endtask

task run();
    int commited = 0;
    logic [63:0] start_address;

    Block bl, curr_bl;
    bpu_t pred, pred_old;

    ghr = '0;
    phr = '0;

    @(posedge clk);
    curr_bl = blocks.pop_front();
    drv_in.send_addr(curr_bl.cfi_address);
    bl_in_q.push_back(curr_bl);

    forever begin
        @(posedge clk);
        if (bl_out_q.size() > 0 && pred_out_q.size() > 0) begin
            bl   = bl_out_q.pop_front();
            pred = pred_out_q.pop_front();
            cfi_commited += 1;
            predicted += bl.cfi_taken == pred.cfi_taken;
            misp_dir += bl.cfi_taken != pred.cfi_taken;
            if (bl.cfi_taken != pred.cfi_taken) drv_in.send_ret_flush();
            if (bl.cfi_taken) begin
                cfi_taken += 1;
            end else begin
                cfi_not_taken += 1;
            end
            if (pred.cfi_taken && bl.cfi_taken == pred.cfi_taken) begin
                predicted_taken += 1;
            end else if (~pred.cfi_taken && bl.cfi_taken == pred.cfi_taken) begin
                predicted_not_taken += 1;
            end
            drv_ret.send(bl, pred, 1'b0, 1'b0);
            commited += 1;

            if (blocks.size() == 0) begin
                break;
            end

            curr_bl = blocks.pop_front();
            drv_in.send_addr(curr_bl.cfi_address);
            bl_in_q.push_back(curr_bl);
        end

        if (drv_bpu.box.num() > 0) begin
            drv_bpu.box.get(pred);
            pred_in_q.push_back(pred);
        end
    end
endtask

initial begin
    Block bl;
    bpu_t pred;
    forever begin
        @(posedge clk);
        if (pred_in_q.size() > 0 && bl_in_q.size() > 0) begin
            bl = bl_in_q.pop_front();
            pred = pred_in_q.pop_front();
            bl_out_q.push_back(bl);
            pred_out_q.push_back(pred);
        end

    end
end

string arr [$];
string tmp;
int fd_f;


initial begin
    rst_n <= 1'b0;
    drv_ret = new(bpu_iface);
    drv_bpu = new(bpu_iface);
    drv_in = new(bpu_iface);
    fork
        drv_ret.run();
        drv_bpu.run();
        drv_in.run();
    join_none
    #10
    rst_n <= 1'b1;
    #50
    fd_f = $fopen("files", "r");
    while (!$feof(fd_f)) begin
        $fscanf(fd_f, "%s", tmp);
        arr.push_back(tmp);
    end
    $fclose(fd_f);

    for (int i = 0; i < 1; i++) begin
        load_trace("trace/test.trace");
        run();
        $display("iteration %d", i);
    end
    print_statistics();

    $finish;
end


initial begin
    $vcdplusfile("dump.vpd");
    $vcdpluson(0, "tb");
    $vcdplusmemon();
end


endmodule : tb
