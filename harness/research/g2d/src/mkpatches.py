#!/usr/bin/env python3
# Build the h616-g2d patch files for the sunxi-7.3 series from src/ (new files) and
# string edits of the files as they stand after the rest of the series (the work-cumul tree).
import os, subprocess, sys, tempfile
H = '/home/aruni/orangepizero2'
L = f'{H}/kernel-check/work-cumul/linux-7.3.1'
SRC = f'{H}/harness/research/g2d/src'
OUT = sys.argv[1] if len(sys.argv) > 1 else f'{H}/wt-g2d/patch/kernel/archive/sunxi-7.3/patches.media/h616-g2d'
os.makedirs(OUT, exist_ok=True)
HDR = ('From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001\n'
       'From: Arun Iyengar <aiyengar1990@gmail.com>\nDate: Fri, 6 Nov 2026 12:00:00 +0000\n')
TRAIL = 'Assisted-by: LLM\nSigned-off-by: Arun Iyengar <aiyengar1990@gmail.com>\n---\n\n'

def udiff(path, old, new):
    with tempfile.TemporaryDirectory() as d:
        a = os.path.join(d, 'a'); b = os.path.join(d, 'b')
        if old is None:
            a = '/dev/null'
        else:
            open(a, 'w').write(old)
        open(b, 'w').write(new)
        r = subprocess.run(['diff', '-u', '--label', f'a/{path}' if old is not None else '/dev/null',
                            '--label', f'b/{path}', a, b], capture_output=True, text=True)
        assert r.returncode == 1, (path, r.returncode, r.stderr)
        return r.stdout

def edit(path, pairs):
    s = open(f'{L}/{path}').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old)
        s = s.replace(old, new)
    return udiff(path, open(f'{L}/{path}').read(), s)

def newfile(path, src):
    return udiff(path, None, open(src).read())

def write(name, subject, body, diffs):
    txt = HDR + f'Subject: {subject}\n\n' + body.strip('\n') + '\n\n' + TRAIL + ''.join(diffs)
    open(f'{OUT}/{name}', 'w').write(txt)
    print('wrote', name, len(txt))

# 1. driver
write('media-sunxi-Add-Allwinner-H616-G2D-colour-conversion-and-scaling-driver.patch',
      'media: sunxi: Add Allwinner H616 G2D colour conversion and scaling driver',
      '''
The G2D of the Allwinner H616 is a 2D graphics engine: a display-engine
style mixer (one video overlay with a coarse decimator, a scaler, three
UI overlays, a blender with three colour space converters and a
write-back unit) plus a separate rotation engine. It sits behind master
6 of the SoC IOMMU.

Add a V4L2 mem2mem driver for the mixer path video overlay -> scaler ->
blender -> write-back: it converts between the 32/24/16-bit RGB formats
and the 4:2:0 / 4:2:2 semi-planar and planar YUV formats, scales by any
ratio (the overlay decimates by up to 8x horizontally and 4x vertically
in front of the 4-tap scaler, which also upsamples the chroma), and
converts colour spaces with matrices computed from the V4L2 colorimetry
of the output queue (BT.601, BT.709, BT.2020, SMPTE 240M; limited and
full range). Every job runs from the reset state of the mixer, a
watchdog returns the buffers with an error when the finish interrupt
does not come, and the clocks and reset are handled with runtime PM.

The H616 user manual (v1.0, 4.3) lists the block, its clocks, reset and
IOMMU master but documents no registers; the register layout and the
programming sequence follow the GPL BSP driver (drivers/char/sunxi_g2d),
used as a reference. Rotation and flipping, the UI overlays and the
10-bit formats are left for later.
''',
      [edit('drivers/media/platform/sunxi/Kconfig',
            [('source "drivers/media/platform/sunxi/sun50i-di300/Kconfig"\n',
              'source "drivers/media/platform/sunxi/sun50i-di300/Kconfig"\nsource "drivers/media/platform/sunxi/sun50i-g2d/Kconfig"\n')]),
       edit('drivers/media/platform/sunxi/Makefile',
            [('obj-y\t\t+= sun50i-di300/\n', 'obj-y\t\t+= sun50i-di300/\nobj-y\t\t+= sun50i-g2d/\n')]),
       newfile('drivers/media/platform/sunxi/sun50i-g2d/Kconfig', f'{SRC}/sun50i-g2d/Kconfig'),
       newfile('drivers/media/platform/sunxi/sun50i-g2d/Makefile', f'{SRC}/sun50i-g2d/Makefile'),
       newfile('drivers/media/platform/sunxi/sun50i-g2d/sun50i-g2d.c', f'{SRC}/sun50i-g2d/sun50i-g2d.c'),
       newfile('drivers/media/platform/sunxi/sun50i-g2d/sun50i-g2d.h', f'{SRC}/sun50i-g2d/sun50i-g2d.h')])

# 2. binding
write('dt-bindings-media-Add-Allwinner-H616-G2D.patch',
      'dt-bindings: media: Add Allwinner H616 G2D',
      '''
Add a binding for the G2D 2D graphics engine of the Allwinner H616: one
register block, one interrupt, the bus, module and MBUS clocks, the bus
reset and the IOMMU master.
''',
      [newfile('Documentation/devicetree/bindings/media/allwinner,sun50i-h616-g2d.yaml',
               f'{SRC}/allwinner,sun50i-h616-g2d.yaml')])

# 3. CCU reset
write('clk-sunxi-ng-h616-Add-the-G2D-bus-reset.patch',
      'clk: sunxi-ng: h616: Add the G2D bus reset',
      '''
The H616 CCU already models the G2D module, bus and MBUS clocks but not
the reset in bit 16 of the G2D bus gating reset register (H616 user
manual v1.0, 3.3.5.56, G2D_BGR_REG at 0x063c). Add it after the last
reset so the existing indices stay unchanged.
''',
      [edit('drivers/clk/sunxi-ng/ccu-sun50i-h616.c',
            [('\t[RST_BUS_LVDS]\t\t= { 0xbac, BIT(16) },\n',
              '\t[RST_BUS_LVDS]\t\t= { 0xbac, BIT(16) },\n\t[RST_BUS_G2D]\t\t= { 0x63c, BIT(16) },\n')]),
       edit('include/dt-bindings/reset/sun50i-h616-ccu.h',
            [('#define RST_BUS_LVDS\t\t63\n', '#define RST_BUS_LVDS\t\t63\n#define RST_BUS_G2D\t\t64\n')])])

# 4. DT node
write('arm64-dts-allwinner-h616-Add-the-G2D-node.patch',
      'arm64: dts: allwinner: h616: Add the G2D node',
      '''
Add the G2D 2D graphics engine at 0x01480000 (H616 user manual v1.0,
memory map and interrupt 122 = GIC SPI 90) with its bus, module and
MBUS clocks, the bus reset and IOMMU master 6 (table 3-8). The driver
sets the module clock rate itself.
''',
      [edit('arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi',
            [('''			interrupts = <GIC_SPI 89 IRQ_TYPE_LEVEL_HIGH>;
			iommus = <&iommu 1>;
		};

''', '''			interrupts = <GIC_SPI 89 IRQ_TYPE_LEVEL_HIGH>;
			iommus = <&iommu 1>;
		};

		g2d: g2d@1480000 {
			compatible = "allwinner,sun50i-h616-g2d";
			reg = <0x01480000 0x40000>;
			interrupts = <GIC_SPI 90 IRQ_TYPE_LEVEL_HIGH>;
			clocks = <&ccu CLK_BUS_G2D>, <&ccu CLK_G2D>,
				 <&ccu CLK_MBUS_G2D>;
			clock-names = "bus", "mod", "mbus";
			resets = <&ccu RST_BUS_G2D>;
			iommus = <&iommu 6>;
		};

''')])])
