##------------------------------------------------------------------------------
## Constraint File : zybo_z7_10.xdc
## Target Board    : Digilent Zybo Z7-10 (xc7z010clg400-1)
## Project         : Finpro_PSD - Brankas Digital (brankas_top)
## Note            : Only pins physically wired on Zybo Z7-10 are used
##                   (excludes JB and RGB LED 5 which are Zybo Z7-20 only).
##------------------------------------------------------------------------------

## System Clock (125 MHz -> 8.000 ns period)
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { clk }]; #IO_L12P_T1_MRCC_35 Sch=sysclk
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { clk }];

## Push Buttons (Active-High on Zybo Z7-10)
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { btn_inc }];    #IO_L12N_T1_MRCC_35 Sch=btn[0]
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { btn_next }];   #IO_L24N_T3_34 Sch=btn[1]
set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports { btn_relock }]; #IO_L10P_T1_AD11P_35 Sch=btn[2]
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports { rst }];        #IO_L7P_T1_34 Sch=btn[3]

## Slide Switches (1-Digit BCD XOR Key: 0..9)
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { sw_key[0] }];  #IO_L19N_T3_VREF_35 Sch=sw[0]
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { sw_key[1] }];  #IO_L24P_T3_34 Sch=sw[1]
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports { sw_key[2] }];  #IO_L4N_T0_34 Sch=sw[2]
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { sw_key[3] }];  #IO_L9P_T1_DQS_34 Sch=sw[3]

## Discrete LEDs (Digit Position 0..3 / Lockout Tier Bar-Graph / Unlocked All-On)
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led_pos[0] }]; #IO_L23P_T3_35 Sch=led[0]
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led_pos[1] }]; #IO_L23N_T3_35 Sch=led[1]
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led_pos[2] }]; #IO_0_35 Sch=led[2]
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led_pos[3] }]; #IO_L3N_T0_DQS_AD1N_35 Sch=led[3]

## RGB LED 6 (Status Indicator: Red=Alarm/Lockout, Green=Unlocked, Blue=Entry)
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led_alarm }];    #IO_L18P_T2_34 Sch=led6_r
set_property -dict { PACKAGE_PIN F17   IOSTANDARD LVCMOS33 } [get_ports { led_unlocked }]; #IO_L6N_T0_VREF_35 Sch=led6_g
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { led_entry }];    #IO_L8P_T1_AD10P_35 Sch=led6_b

## Pmod Header JD -> 2-Digit 7-Segment Display (Digilent Pmod SSD 1-to-1 Pinout)
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[0] }]; #JD1 (a)
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[1] }]; #JD2 (b)
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[2] }]; #JD3 (c)
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[3] }]; #JD4 (d)
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[4] }]; #JD7 (e)
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[5] }]; #JD8 (f)
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { seg7_out[6] }]; #JD9 (g)
set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 } [get_ports { seg7_sel }];    #JD10 (Digit Select / Cat)

## Pmod Header JC -> 14-Segment Display Segments a..h (bits 0..7)
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[0] }]; #JC1 (seg a)
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[1] }]; #JC2 (seg b)
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[2] }]; #JC3 (seg c)
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[3] }]; #JC4 (seg d)
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[4] }]; #JC7 (seg e)
set_property -dict { PACKAGE_PIN Y14   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[5] }]; #JC8 (seg f)
set_property -dict { PACKAGE_PIN T12   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[6] }]; #JC9 (seg g / g1)
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[7] }]; #JC10 (seg h / g2)

## Pmod Header JE -> 14-Segment Display Segments i..n (bits 8..13), Common Enable, & Buzzer
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[8] }];  #JE1 (seg i)
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[9] }];  #JE2 (seg j)
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[10] }]; #JE3 (seg k)
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[11] }]; #JE4 (seg l)
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[12] }]; #JE7 (seg m)
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { seg14_out[13] }]; #JE8 (seg n)
set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports { seg14_en }];      #JE9 (14-seg common enable)
set_property -dict { PACKAGE_PIN Y17   IOSTANDARD LVCMOS33 } [get_ports { buzzer_out }];    #JE10 (Alarm buzzer / actuator)

## Optional Pmod Header JA (XADC / Spare GPIO for External Solenoid/Relay Expansion)
#set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { ja[0] }]; #IO_L21P_T3_DQS_AD14P_35 Sch=ja_p[1]
#set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { ja[1] }]; #IO_L22P_T3_AD7P_35 Sch=ja_p[2]
#set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { ja[2] }]; #IO_L24P_T3_AD15P_35 Sch=ja_p[3]
#set_property -dict { PACKAGE_PIN K14   IOSTANDARD LVCMOS33 } [get_ports { ja[3] }]; #IO_L24N_T3_AD15N_35 Sch=ja_p[4]
#set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { ja[4] }]; #IO_L21N_T3_DQS_AD14N_35 Sch=ja_n[1]
#set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { ja[5] }]; #IO_L22N_T3_AD7N_35 Sch=ja_n[2]
#set_property -dict { PACKAGE_PIN J16   IOSTANDARD LVCMOS33 } [get_ports { ja[6] }]; #IO_L24P_T3_35 Sch=ja_n[3]
#set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { ja[7] }]; #IO_L24N_T3_35 Sch=ja_n[4]
