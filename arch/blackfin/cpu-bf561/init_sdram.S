#define ASSEMBLY

#include <config.h>
#include <asm/blackfin.h>
#include <asm/mem_init.h>
.global init_sdram;

init_sdram:
	[--SP] = ASTAT;
	[--SP] = RETS;
	[--SP] = (R7:0);
	[--SP] = (P5:0);

#ifndef BF537_UART_BOOT

#ifdef CONFIG_BF537
	/* Enable PHY CLK buffer output */
	p0.h = hi(VR_CTL);
	p0.l = lo(VR_CTL);
	r0.l = w[p0];
	bitset(r0, 14);
	w[p0] = r0.l;
	ssync;
#endif
	/*
         * PLL_LOCKCNT - how many SCLK Cycles to delay while PLL becomes stable
         */
	p0.h = hi(PLL_LOCKCNT);
	p0.l = lo(PLL_LOCKCNT);
	r0 = 0x640(Z);
	w[p0] = r0.l;
	ssync;

	/*
         * Put SDRAM in self-refresh, incase anything is running
         */
        P2.H = hi(EBIU_SDGCTL);
        P2.L = lo(EBIU_SDGCTL);
        R0 = [P2];
        BITSET (R0, 24);
        [P2] = R0;
        SSYNC;

	/* Make sure PLL wakeup is enabled as BOOT ROM seems to disable
	 * it. (R7 and R6 used to store original value!)
	 */
	p0.h = hi(SIC_IWR);
	p0.l = lo(SIC_IWR);
	r7 = [p0];
	r0 = 1;
	[p0] = r0;
#ifdef SICA_IWR1
	p0.h = hi(SICA_IWR1);
	p0.l = lo(SICA_IWR1);
	r6 = [p0];
	r0 = 0;
	[p0] = r0;
#endif
	ssync;

#ifdef CONFIG_VSEL
	/*
	 *
	 * Set Voltage Regulator.
	 */

	p2.h = hi(VR_CTL);
	p2.l = lo(VR_CTL);
	r0 = w[p2];
	r1 = ~0xf0;
	r0 = r0 & r1;
	r1 = CONFIG_VSEL & 0x0f;
	r1 = r1 << 4;
	r0 = r0 | r1;
	cli r2;
	ssync;
	w[p2] = r0.l;
	idle;
	sti r2;
#endif

        /*
         *  Set PLL_CTL with the value that we calculate in R0
         *   - [14:09] = MSEL[5:0] : CLKIN / VCO multiplication factors
         *   - [8]     = BYPASS    : BYPASS the PLL, run CLKIN into CCLK/SCLK
         *   - [7]     = output delay (add 200ps of delay to mem signals)
         *   - [6]     = input delay (add 200ps of input delay to mem signals)
         *   - [5]     = PDWN      : 1=All Clocks off
         *   - [3]     = STOPCK    : 1=Core Clock off
         *   - [1]     = PLL_OFF   : 1=Disable Power to PLL
         *   - [0]     = DF        : 1=Pass CLKIN/2 to PLL / 0=Pass CLKIN to PLL
         *   all other bits set to zero
         */

	/* first, explicitly enable DF, due to anomaly 05000242 */
	p0.h = hi(PLL_CTL);
	p0.l = lo(PLL_CTL);             /* Load the address                */
	r0.l = w[p0];
	r1 = 1;
	r0 = r0 | r1;
	cli r2;
	ssync;
	w[p0] = r0.l;
	idle;
	sti r2;

        r0 = CONFIG_VCO_MULT & 63;      /* Load the VCO multiplier         */
        r0 = r0 << 9;                   /* Shift it over,                  */
        r1 = CONFIG_CLKIN_HALF;        /* Do we need to divide CLKIN by 2?*/
        r0 = r1 | r0;
        r1 = CONFIG_PLL_BYPASS;         /* Bypass the PLL?                 */
        r1 = r1 << 8;                   /* Shift it over                   */
        r0 = r1 | r0;                   /* add them all together           */

        p0.h = hi(PLL_CTL);
        p0.l = lo(PLL_CTL);             /* Load the address                */
        cli r2;                         /* Disable interrupts              */
	ssync;
        w[p0] = r0.l;                   /* Set the value                   */
        idle;                           /* Wait for the PLL to stablize    */
        sti r2;                         /* Enable interrupts               */

check_again:
	p0.h = hi(PLL_STAT);
	p0.l = lo(PLL_STAT);
	R0 = W[P0](Z);
	CC = BITTST(R0,5);
	if ! CC jump check_again;

	/* Configure SCLK & CCLK Dividers */
       	r0 = (CONFIG_CCLK_ACT_DIV | CONFIG_SCLK_DIV);
        p0.h = hi(PLL_DIV);
        p0.l = lo(PLL_DIV);
        w[p0] = r0.l;
        ssync;
#endif

	/*
         * We now are running at speed, time to set the Async mem bank wait states
	 * This will speed up execution, since we are normally running from FLASH.
	 */

        p2.h = (EBIU_AMBCTL1 >> 16);
        p2.l = (EBIU_AMBCTL1 & 0xFFFF);
        r0.h = (AMBCTL1VAL >> 16);
        r0.l = (AMBCTL1VAL & 0xFFFF);
        [p2] = r0;
        ssync;

        p2.h = (EBIU_AMBCTL0 >> 16);
        p2.l = (EBIU_AMBCTL0 & 0xFFFF);
        r0.h = (AMBCTL0VAL >> 16);
        r0.l = (AMBCTL0VAL & 0xFFFF);
        [p2] = r0;
        ssync;

        p2.h = (EBIU_AMGCTL >> 16);
        p2.l = (EBIU_AMGCTL & 0xffff);
        r0 = AMGCTLVAL;
        w[p2] = r0;
        ssync;

	/*
	 * Now, Initialize the SDRAM,
	 * start with the SDRAM Refresh Rate Control Register
         */
	p0.l = lo(EBIU_SDRRC);
        p0.h = hi(EBIU_SDRRC);
        r0 = mem_SDRRC;
        w[p0] = r0.l;
        ssync;

	/*
	 * SDRAM Memory Bank Control Register - bank specific parameters
	 */
	p0.l = (EBIU_SDBCTL & 0xFFFF);
	p0.h = (EBIU_SDBCTL >> 16);
	r0 = mem_SDBCTL;
	w[p0] = r0.l;
	ssync;

	/*
	 * SDRAM Global Control Register - global programmable parameters
	 * Disable self-refresh
	 */
	P2.H = hi(EBIU_SDGCTL);
        P2.L = lo(EBIU_SDGCTL);
        R0 = [P2];
        BITCLR (R0, 24);

	/*
         * Check if SDRAM is already powered up, if it is, enable self-refresh
         */
	p0.h = hi(EBIU_SDSTAT);
	p0.l = lo(EBIU_SDSTAT);
	r2.l = w[p0];
	cc = bittst(r2,3);
	if !cc jump skip;
    	NOP;
	BITSET (R0, 23);
skip:
	[P2] = R0;
        SSYNC;

	/* Write in the new value in the register */
        R0.L = lo(mem_SDGCTL);
        R0.H = hi(mem_SDGCTL);
	[P2] = R0;
        SSYNC;
	nop;

	/*
	 * Restore wakeup
	 */
	p0.h = hi(SIC_IWR);
	p0.l = lo(SIC_IWR);
	[p0] = r7;
#ifdef SICA_IWR1
	p0.h = hi(SICA_IWR1);
	p0.l = lo(SICA_IWR1);
	[p0] = r6;
#endif
	ssync;

	(P5:0) = [SP++];
	(R7:0) = [SP++];
	RETS   = [SP++];
	ASTAT  = [SP++];
	RTS;

