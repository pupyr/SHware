class Block;
    int            id;
    logic [PC-1:0] cfi_address;
    logic          cfi_taken;

    function Block copy;
        copy = new ();
        copy.cfi_address    = cfi_address;
        copy.cfi_taken      = cfi_taken;
        copy.id             = id;
        return copy;
    endfunction

    function void parse_from_log(int fd);
        $fscanf(fd, "ca=0x%h t=%b id=%d"
            , this.cfi_address, this.cfi_taken, this.id);
    endfunction
endclass : Block


typedef struct packed {
    logic cfi_taken;
    logic [TAGE_IND-1:0] tage_ind;
} bpu_t;


interface ret_if(input logic clk);
    logic                                       update_i;
    logic                        [TAGE_IND-1:0] tage_ind_i;
    logic                                       taken_i;
    logic       		      [PC -1:0] pc_i;

    clocking mc @(posedge clk);
        output update_i, tage_ind_i, taken_i, pc_i;
    endclocking
endinterface


interface in_if(input logic clk);
    logic bpu_req_i;
    logic [PC -1:0] bpu_addr_i;
    logic bpu_flush_i;
    clocking mc @(posedge clk);
        output bpu_req_i, bpu_addr_i, bpu_flush_i;
    endclocking
endinterface


interface bpu_if(input logic clk);
    logic                                       b1_val_o;
    logic                                       b2_val_o;
    logic                                       b3_val_o;
    logic                                       b4_val_o;
    logic                                       b4_pred_taken_o;
    logic                      [TAGE_IND-1:0]   b3_tage_index_o;
    clocking mc @(posedge clk);
        input b1_val_o, b2_val_o, b3_val_o, b4_val_o, b4_pred_taken_o, b3_tage_index_o;
    endclocking
endinterface : bpu_if

class bpu_trans;
    Block bl;
    bpu_t  pred;
    bit        misp;
    bit        flush;

    function bpu_trans copy;
        copy = new();
        copy.bl = bl;
        copy.pred = pred;
        copy.misp = misp;
        copy.flush = flush;
        return copy;
    endfunction

endclass



class ret_driver;
   virtual bpu_if vif;

   mailbox #(bpu_trans) mbox;

    function new(virtual ret_if if0);
        vif = if0;
        mbox = new();
    endfunction

    task run();
        bpu_trans trans;
        int res;
        int timeout = 0;
        forever begin
            @(vif.mc);

            res = mbox.try_peek(trans);

            vif.mc.update_i           <= 1'b0;
            vif.mc.tage_ind_i           <= '0;
            vif.mc.taken_i              <= '0;
            vif.mc.pc_i                 <= '0;

            if (res == 1) begin
                vif.mc.update_i           <= 1'b1;
                vif.mc.tage_ind_i         <= trans.pred.tage_ind;
                vif.mc.taken_i    	  <= trans.bl.cfi_taken;
                vif.mc.pc_i               <= trans.bl.cfi_address;
                mbox.get(trans);
                timeout = 0;
            end else begin
                timeout += 1;
            end
        end
    endtask : run

    task send(Block bl, bpu_t pred, bit misp, bit flush);
        bpu_trans t = new();
        t.pred = pred;
        t.bl = bl;
        t.misp = misp;
        t.flush = flush;
        mbox.put(t.copy());
    endtask : send
endclass : ret_driver

class in_driver;
    virtual in_if vif;

    mailbox #(logic [PC -1:0]) force_box;
    mailbox #(bit) ret_flush_box;

    function new(virtual bpu_if if0);
        vif = if0;
        force_box = new();
        ret_flush_box = new();
    endfunction

    task run();
        int res;
        bit dummy;
        bit cfi_taken;
        logic [PC -1:0] force_addr;

        forever begin
            @(vif.mc);

            vif.mc.bpu_req_i <= 1'b0;
            vif.mc.bpu_flush_i <= 1'b0;

            res = force_box.try_get(force_addr);
            if (res == 1) begin
                vif.mc.bpu_req_i     <= 1'b1;
                vif.mc.bpu_addr_i    <= force_addr;
            end

            res = ret_flush_box.try_get(dummy);
            if (res == 1) begin
                vif.mc.bpu_flush_i <= 1'b1;
            end
        end
    endtask

    task send_force_addr(logic [PC -1:0] addr);
        force_box.put(addr);
    endtask

    task send_ret_flush();
        ret_flush_box.put(1'b1);
    endtask

endclass : in_driver


class bpu_driver;

    virtual bpu_if vif;
    mailbox #(bpu_t) box;
    mailbox #(bit) flush_box;
    bpu_t b1, b2, b3, b4, b5;
    logic p1, p2, p3, p4, p5;

    function new(virtual bpu_if if0);
        vif = if0;
        box = new();
        flush_box = new();
    endfunction

    task run();
        bit flush;

        forever begin
            @(vif.mc);
            flush = 0;
            flush_box.try_get(flush);
            if (flush == 1) begin
                {p1, p2, p3, p4, p5} <= '0;
                box = new();
            end else begin
                p2 <= p1; p3 <= p2; p4 <= p3; p5 <= p4;
       
                p1 <= vif.mc.b1_val_o; 
            
                b1 <= '0;
                b2 <= b1;
                b3 <= b2;
                b4 <= b3;
                b5 <= b4;

                if (vif.mc.b1_val_o) begin
                    b1.cfi_taken        <= 'x;
                end

                if (vif.mc.b2_val_o) begin
                    p2 <= 1'b1;
                end else begin
                    p2 <= 1'b0;
                end

                if (vif.mc.b3_val_o) begin
                    p3                  <= 1;
                    b3.tage_ind         <= vif.mc.b3_tage_index_o;
                end else begin
                    p3 <= 1'b0;
                end

                if (vif.mc.b4_val_o) begin
                    b4.cfi_taken        <= vif.mc.b4_pred_taken_o;
                end

                if (p5) begin
                    box.put(b5);
                end
            end
        end
    endtask : run

    task flush();
       
        flush_box.put(1'b1);
    endtask : flush
endclass : bpu_driver
