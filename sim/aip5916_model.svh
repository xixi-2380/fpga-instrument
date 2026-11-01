`ifndef AIP5916_MODEL_SVH
`define AIP5916_MODEL_SVH
// Wire-level single-byte AiP5916 model, deliberately rejects burst reads.
module aip5916_model(input wire rst,present,input wire [15:0] touch_keys,
 inout wire scl,sda,output wire int_n);
 reg slave_low=0;assign sda=slave_low?1'b0:1'bz;
 assign int_n=(present && |touch_keys)?1'b0:1'b1;
 reg [7:0] registers[0:63];
 localparam RX=0,ACK=1,TX=2,MASTER_ACK=3,WAIT_STOP=4;
 integer state=WAIT_STOP,next_state=RX,bit_count=0,byte_count=0;
 integer writes=0,reads=0,nacks=0,starts=0,stops=0;
 reg [7:0] shift=0,reg_address=0,tx_byte=0;
 reg address_phase=1,expect_register=0,ack_seen=0,accepted=0;
 reg mismatch=0; // inject a configuration readback mismatch
 always @(posedge rst)begin
  slave_low=0;state=WAIT_STOP;bit_count=0;writes=0;reads=0;nacks=0;starts=0;stops=0;
  for(integer n=0;n<64;n=n+1)registers[n]=0;
 end
 always @(negedge sda)if(scl===1'b1 && !rst)begin
  state=RX;bit_count=0;shift=0;address_phase=1;expect_register=0;starts=starts+1;
 end
 always @(posedge sda)if(scl===1'b1 && !rst)begin state=WAIT_STOP;slave_low=0;stops=stops+1;end
 always @(posedge scl)if(!rst)begin
  case(state)
   RX:begin
    shift={shift[6:0],sda};
    if(bit_count==7)begin
     bit_count=0;accepted=present;next_state=RX;
     if(address_phase)begin
      if(shift[7:1]!=7'h56)$fatal(1,"AiP5916 wrong wire address %h",shift);
      address_phase=0;expect_register=!shift[0];
      if(shift[0])begin
       next_state=TX;reads=reads+1;
       if(reg_address==8'h34)tx_byte=touch_keys[7:0];
       else if(reg_address==8'h35)tx_byte=touch_keys[15:8];
       else tx_byte=registers[reg_address[5:0]] ^ (mismatch?8'h01:8'h00);
      end
     end else if(expect_register)begin reg_address=shift;expect_register=0;end
     else begin
      if(reg_address!=8'h3a && registers[6'h3a]!=8'h5a)$fatal(1,"config write outside SYSCON mode");
      registers[reg_address[5:0]]=shift;writes=writes+1;next_state=WAIT_STOP;
     end
     if(!present)begin next_state=WAIT_STOP;nacks=nacks+1;end
     state=ACK;ack_seen=0;
    end else bit_count=bit_count+1;
   end
   ACK:ack_seen=1;
   TX:if(bit_count==7)begin state=MASTER_ACK;bit_count=0;end else bit_count=bit_count+1;
   MASTER_ACK:begin
    if(sda!==1'b1)$fatal(1,"AiP5916 permits only single-byte reads followed by NACK");
    state=WAIT_STOP;
   end
  endcase
 end
 always @(negedge scl)if(!rst)begin
  case(state)
   ACK:if(!ack_seen)slave_low=accepted;
    else begin
     slave_low=0;state=next_state;bit_count=0;
     if(state==TX)slave_low=!tx_byte[7];
    end
   TX:slave_low=!tx_byte[7-bit_count];
   MASTER_ACK,WAIT_STOP:slave_low=0;
  endcase
 end
endmodule
`endif
