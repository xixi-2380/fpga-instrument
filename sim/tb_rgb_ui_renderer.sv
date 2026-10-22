`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_ui_renderer;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,frame_start=0,status_valid=0,de=0,hs=0,vs=0;
    reg [19:0] status=0;
    reg [10:0] x=0,y=0;
    wire [23:0] rgb;
    wire deo,hso,vso;
    integer checks=0,i,j,k,n,fd;
    reg [23:0] expected,old_rgb;
    reg [19:0] frozen;
    string out_dir;
    rgb_ui_renderer dut(clk,rst,frame_start,status_valid,status,x,y,de,hs,vs,rgb,deo,hso,vso);

    task pixel(input integer px,py,input bit enable_pixel);
        begin
            @(negedge clk);x=px;y=py;de=enable_pixel;hs=px%2;vs=py%2;
            old_rgb=rgb;
            #1;`CHECK(rgb===old_rgb,"RGB output changes only on clock edge")
            @(posedge clk);#1;
            `CHECK({hso,vso}==={hs,vs},"HS and VS delayed with RGB")
            `CHECK(deo===(enable_pixel && px<800 && py<480),"DE clips to active rectangle")
            `CHECK((^rgb)!==1'bx,"all output color bits known")
            if(!enable_pixel || px>=800 || py>=480)
                `CHECK(rgb==0,"blanking and out-of-range coordinates output black")
        end
    endtask
    task publish(input [19:0] data,input bit valid_data);
        begin
            @(negedge clk);de=0;frame_start=1;status_valid=valid_data;status=data;
            @(negedge clk);frame_start=0;status_valid=0;
        end
    endtask
    initial begin
        if(!$value$plusargs("SIM_OUT_DIR=%s",out_dir))out_dir=".";
        @(posedge clk);#1;`CHECK({rgb,deo,hso,vso}==0,"reset blanks RGB and control")
        @(negedge clk);rst=0;
        // Screen preview is a real DUT raster with synthetic test status.
        frozen={1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,2'd1,6'd4,6'd12};
        publish(frozen,1);
        fd=$fopen({out_dir,"/ui_preview.ppm"},"wb");
        `CHECK(fd!=0,"open raster preview")
        $fwrite(fd,"P6\n800 480\n255\n");
        for(j=0;j<480;j=j+1)begin
            for(i=0;i<800;i=i+1)begin
                pixel(i,j,1);
                $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                if(j==270 && i>=48 && i<752)begin
                    expected=(((i-48)%22<20) && ((i-48)/22<12))?24'h35d5cf:
                        (((i-48)%22<20)?24'h101826:24'h1c293b);
                    `CHECK(rgb==expected,"independent active bar count and gaps")
                end
                // New input status half way through a frame must not tear it.
                if(i==400 && j==240)begin status=20'hfffff;status_valid=1;end
                `CHECK(dut.state==frozen,"status snapshot held for entire raster")
            end
        end
        $fclose(fd);
        publish(20'hfffff,0);
        `CHECK(dut.state==frozen,"invalid frame-boundary input preserves old snapshot")
        // Count boundary checks: every slot, 0..32 plus saturated invalid input.
        for(n=0;n<=33;n=n+1)begin
            publish({8'b0,6'(n),6'(n)},1);
            for(k=0;k<32;k=k+1)begin
                pixel(48+k*22,270,1);
                `CHECK(rgb==((k<n)?24'h35d5cf:24'h101826),"active voice count boundary")
                pixel(48+k*22,358,1);
                `CHECK(rgb==((k<n)?24'h65d48b:24'h101826),"held voice count boundary")
            end
        end
        // Fixed glyph stroke probes confirm the displayed labels change.
        publish(20'h08000,1);pixel(264,116,1);
        `CHECK(rgb==24'h35d5cf,"keyboard label starts with K left stroke")
        publish(20'h0c000,1);pixel(264,116,1);
        `CHECK(rgb==24'h1c293b,"score label starts with S inset stroke")
        publish(20'h08000,1);pixel(432,164,1);
        `CHECK(rgb==24'h1c293b,"sine label starts with S inset stroke")
        publish(20'h09000,1);pixel(432,164,1);
        `CHECK(rgb==24'he8eef5,"flute label starts with F full stroke")
        publish(20'h0a000,1);pixel(432,164,1);
        `CHECK(rgb==24'he8eef5,"reed label starts with R full stroke")
        publish(20'h0b000,1);pixel(436,164,1);
        `CHECK(rgb==24'hf4c46b,"invalid timbre has visible question mark")
        publish(20'h78000,1);
        pixel(48,408,1);`CHECK(rgb==24'h65d48b,"audio ready indicator green")
        pixel(220,404,1);`CHECK(rgb==24'hff6578,"score error red")
        pixel(384,404,1);`CHECK(rgb==24'hff6578,"underrun red")
        pixel(580,404,1);`CHECK(rgb==24'hf4c46b,"ghost amber")
        publish(0,1);pixel(48,408,1);
        `CHECK(rgb==24'hf4c46b,"audio not ready amber")
        // Test bars: all columns checked against an independent color table.
        publish(20'h80000,1);
        for(i=0;i<800;i=i+1)begin
            pixel(i,200,1);
            case(i/100)
                0:expected=24'hffffff;1:expected=24'hffff00;
                2:expected=24'h00ffff;3:expected=24'h00ff00;
                4:expected=24'hff00ff;5:expected=24'hff0000;
                6:expected=24'h0000ff;7:expected=0;
            endcase
            if(i==0 || i==799)expected=24'he8eef5;
            `CHECK(rgb==expected,"test pattern color order and horizontal border")
        end
        pixel(400,0,1);`CHECK(rgb==24'he8eef5,"top border")
        pixel(400,479,1);`CHECK(rgb==24'he8eef5,"bottom border")
        pixel(800,479,1);pixel(799,480,1);pixel(2047,2047,1);
        pixel(400,200,0);
        @(negedge clk);rst=1;
        @(posedge clk);#1;
        `CHECK({rgb,deo,hso,vso}==0 && dut.state==0,"mid-frame reset clears stale state")
        $display("PASS tb_rgb_ui_renderer checks=%0d",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"UI renderer timeout");end
endmodule
