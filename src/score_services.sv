`timescale 1ns/1ps
// Reference-domain composition only: independent control, protocol, library,
// and physical Flash driver. No UI rendering or audio synthesis here.
module score_services #(parameter integer FLASH_WRITES=1)(
 input wire clk,rst,action_valid,output wire action_ready,input wire [3:0] action,
 output wire [79:0] status,
 input wire song_valid,upload_active,input wire [1:0] play_state,
 input wire [15:0] total_notes,input wire [31:0] song_duration,song_crc,
 output wire local_valid,input wire local_ready,output wire [1:0] local_command,input wire local_done,input wire [7:0] local_error,
 output wire storage_lock,input wire storage_ready,output wire storage_write,storage_invalidate,
 output wire [11:0] storage_address,output wire [63:0] storage_wdata,input wire [63:0] storage_rdata,
 output wire storage_import,output wire [15:0] storage_count,output wire [31:0] storage_crc,input wire storage_done,input wire [7:0] storage_error,
 input wire extension_valid,output wire extension_ready,input wire [7:0] extension_command,input wire [8:0] extension_length,input wire [63:0] extension_payload,
 output wire extension_response_valid,input wire extension_response_ready,output wire [4:0] extension_response_length,output wire [159:0] extension_response,
 output wire flash_cs_n,flash_sck,flash_mosi,input wire flash_miso,output wire flash_wp_n,flash_hold_n);
 wire library_ready,library_busy,library_init,library_done,loaded_valid;
 wire [4:0] selected,loaded_index;wire [31:0] entries;
 wire [15:0] job_id;wire [1:0] job_state;wire [7:0] library_error,control_error;
 wire control_busy,control_done,local_library_valid,remote_library_valid;
 wire [1:0] local_library_command,remote_library_command;wire [4:0] local_library_index,remote_library_index;
 wire [55:0] remote_name;wire [4:0] remote_lookup;
 wire [159:0] lookup_data;
 wire remote_pending=extension_valid || !extension_ready || extension_response_valid;
 wire [4:0] lookup_index=remote_pending?remote_lookup:selected;
 reg [4:0] previous_lookup,selected_meta_index;reg [159:0] selected_meta;
 wire fr,fv,fd,fi,fs,bw;wire [1:0] fo;wire [23:0] fa,jedec;wire [8:0] fl;
 wire [7:0] fe,bi,bd,ri,rd,s1,s2,s3;
 wire writable=FLASH_WRITES!=0 && fs && s1[7:2]==0 && !s1[0] && !s2[6] && !s2[0] && !s2[7] && !s3[2];
 assign action_ready=!control_busy && !remote_pending;
 assign status={3'd0,job_id,job_state,fs,jedec,(selected_meta_index==selected?selected_meta[31:16]:16'd0),play_state,
  (control_error!=0?control_error:library_error),library_init,library_busy,entries[selected],selected};
 always @(posedge clk or posedge rst)begin
  if(rst)begin previous_lookup<=0;selected_meta_index<=0;selected_meta<=0;end
  else begin previous_lookup<=lookup_index;if(lookup_index==selected && previous_lookup==selected)begin selected_meta<=lookup_data;selected_meta_index<=selected;end end
 end
 local_score_control control(.clk(clk),.rst(rst),.action_valid(action_valid && action_ready),.action(action),.entries(entries),
 .upload_active(upload_active),.library_busy(library_busy || remote_pending),.song_valid(song_valid),.loaded_valid(loaded_valid),.loaded_index(loaded_index),
 .selected(selected),.busy(control_busy),.done(control_done),.error(control_error),
 .player_valid(local_valid),.player_ready(local_ready),.player_command(local_command),.player_done(local_done),.player_error(local_error),
 .library_valid(local_library_valid),.library_ready(library_ready && !remote_pending),.library_command(local_library_command),.library_index(local_library_index),
 .library_done(library_done),.library_error(library_error));
 score_library_protocol protocol(.clk(clk),.rst(rst),.request_valid(extension_valid),.request_ready(extension_ready),
 .command(extension_command),.length(extension_length),.payload(extension_payload),.response_valid(extension_response_valid),.response_ready(extension_response_ready),
 .response_length(extension_response_length),.response(extension_response),.initialized(library_init),.supported(fs),.writable(writable),
 .library_busy(library_busy),.local_busy(control_busy),.storage_ready(storage_ready),.jedec_id(jedec),.status1(s1),.status2(s2),.status3(s3),.library_error(library_error),
 .job_id(job_id),.job_state(job_state),.ram_crc(song_crc),.library_valid(remote_library_valid),.library_ready(library_ready),.library_command(remote_library_command),
 .library_index(remote_library_index),.library_name(remote_name),.lookup_index(remote_lookup),.lookup_data(lookup_data));
 flash_song_library song_library(.clk(clk),.rst(rst),.request_valid(remote_library_valid || (local_library_valid && !remote_pending)),.request_ready(library_ready),
 .command(remote_library_valid?remote_library_command:local_library_command),.song_index(remote_library_valid?remote_library_index:local_library_index),
 .song_name(remote_library_valid?remote_name:56'd0),.busy(library_busy),.initialized(library_init),.job_id(job_id),.job_state(job_state),.error(library_error),.done(library_done),
 .entries(entries),.loaded_valid(loaded_valid),.loaded_index(loaded_index),.lookup_index(lookup_index),.lookup_data(lookup_data),
 .ram_valid(song_valid),.ram_count(total_notes),.ram_duration(song_duration),.ram_crc(song_crc),
 .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),.storage_address(storage_address),
 .storage_wdata(storage_wdata),.storage_rdata(storage_rdata),.storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),.storage_done(storage_done),.storage_error(storage_error),
 .upload_active(upload_active),.flash_initialized(fi),.flash_supported(fs),.flash_ready(fr),.flash_valid(fv),.flash_op(fo),.flash_address(fa),.flash_length(fl),.flash_done(fd),.flash_error(fe),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd));
 spi_nor_flash flash(.clk(clk),.rst(rst),.request_valid(fv),.request_ready(fr),.operation(fo),.address(fa),.length(fl),.writes_enabled(FLASH_WRITES!=0),
 .done(fd),.error(fe),.initialized(fi),.supported(fs),.jedec_id(jedec),.status1(s1),.status2(s2),.status3(s3),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd),
 .cs_n(flash_cs_n),.sck(flash_sck),.mosi(flash_mosi),.miso(flash_miso),.wp_n(flash_wp_n),.hold_n(flash_hold_n));
endmodule
