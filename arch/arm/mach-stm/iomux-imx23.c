/*
 * (C) Copyright 2010 Juergen Beisert - Pengutronix
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */

#include <common.h>
#include <init.h>
#include <gpio.h>
#include <asm/io.h>
#include <mach/imx-regs.h>

#define HW_PINCTRL_CTRL 0x000
#define HW_PINCTRL_MUXSEL0 0x100
#define HW_PINCTRL_DRIVE0 0x200
#define HW_PINCTRL_PULL0 0x400
#define HW_PINCTRL_DOUT0 0x500
#define HW_PINCTRL_DIN0 0x600
#define HW_PINCTRL_DOE0 0x700

static uint32_t calc_mux_reg(uint32_t no)
{
	/* each register controls 16 pads */
	return ((no >> 4) << 4) + HW_PINCTRL_MUXSEL0;
}

static uint32_t calc_strength_reg(uint32_t no)
{
	/* each register controls 8 pads */
	return  ((no >> 3) << 4) + HW_PINCTRL_DRIVE0;
}

static uint32_t calc_pullup_reg(uint32_t no)
{
	/* each register controls 32 pads */
	return  ((no >> 5) << 4) + HW_PINCTRL_PULL0;
}

static uint32_t calc_output_enable_reg(uint32_t no)
{
	/* each register controls 32 pads */
	return  ((no >> 5) << 4) + HW_PINCTRL_DOE0;
}

static uint32_t calc_output_reg(uint32_t no)
{
	/* each register controls 32 pads */
	return  ((no >> 5) << 4) + HW_PINCTRL_DOUT0;
}

/**
 * @param[in] m One of the defines from iomux-mx23.h to configure *one* pin
 */
void imx_gpio_mode(unsigned m)
{
	uint32_t reg_offset, gpio_pin, reg;

	gpio_pin = GET_GPIO_NO(m);

	/* configure the pad to its function (always) */
	reg_offset = calc_mux_reg(gpio_pin);
	reg = readl(IMX_IOMUXC_BASE + reg_offset) & ~(0x3 << ((gpio_pin % 16) << 1));
	reg |= GET_FUNC(m) << ((gpio_pin % 16) << 1);
	writel(reg, IMX_IOMUXC_BASE + reg_offset);

	/* some pins are disabled when configured for GPIO */
	if ((gpio_pin > 95) && (GET_FUNC(m) == IS_GPIO)) {
		printf("Cannot configure pad %d to GPIO\n", gpio_pin);
		return;
	}

	if (SE_PRESENT(m)) {
		reg_offset = calc_strength_reg(gpio_pin);
		reg = readl(IMX_IOMUXC_BASE + reg_offset) & ~(0x3 << ((gpio_pin % 8) << 2));
		reg |= GET_STRENGTH(m) << ((gpio_pin % 8) << 2);
		writel(reg, IMX_IOMUXC_BASE + reg_offset);
	}

	if (VE_PRESENT(m)) {
		reg_offset = calc_strength_reg(gpio_pin);
		if (GET_VOLTAGE(m) == 1)
			writel(0x1 << (((gpio_pin % 8) << 2) + 2), IMX_IOMUXC_BASE + reg_offset + 4);
		else
			writel(0x1 << (((gpio_pin % 8) << 2) + 2), IMX_IOMUXC_BASE + reg_offset + 8);
	}

	if (PE_PRESENT(m)) {
		reg_offset = calc_pullup_reg(gpio_pin);
		writel(0x1 << (gpio_pin % 32), IMX_IOMUXC_BASE + reg_offset + (GET_PULLUP(m) == 1 ? 4 : 8));
	}

	if (GET_FUNC(m) == IS_GPIO) {
		if (GET_GPIODIR(m) == 1) {
			/* first set the output value */
			reg_offset = calc_output_reg(gpio_pin);
			writel(0x1 << (gpio_pin % 32), IMX_IOMUXC_BASE + reg_offset + (GET_GPIOVAL(m) == 1 ? 4 : 8));
			/* then the direction */
			reg_offset = calc_output_enable_reg(gpio_pin);
			writel(0x1 << (gpio_pin % 32), IMX_IOMUXC_BASE + reg_offset + 4);
		} else {
			writel(0x1 << (gpio_pin % 32), IMX_IOMUXC_BASE + reg_offset + 8);
		}
	}
}