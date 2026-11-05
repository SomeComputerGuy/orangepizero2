#!/usr/bin/env python3
# Port Rockchip develop-6.6 bifrost kbase (g25p0-00eac0) API usage to Linux 7.3.
import re, sys, os, glob
root = sys.argv[1]
def edit(path, fn):
    p = os.path.join(root, path); s = open(p).read(); n = fn(s)
    if n != s: open(p, 'w').write(n); print('patched', path)
def rep(path, a, b, count=1):
    def f(s):
        if a not in s: print('MISSING in', path, ':', a[:60]); return s
        return s.replace(a, b, count)
    edit(path, f)

# Kbuild: $(src) is already absolute-or-relative to the M= dir on 6.13+; do not prefix $(srctree).
for k in ('Kbuild', 'tests/Kbuild'):
    edit(k, lambda s: s.replace('src:=$(if $(patsubst /%,,$(src)),$(srctree)/$(src),$(src))', 'src:=$(abspath $(src))'))
# Rockchip-only OPP/system-monitor hooks: compile them only on Rockchip.
G = lambda a: '#ifdef CONFIG_ARCH_ROCKCHIP\n' + a + '#endif\n'
rep('mali_kbase_defs.h', '#include <soc/rockchip/rockchip_opp_select.h>\n', G('#include <soc/rockchip/rockchip_opp_select.h>\n'))
rep('mali_kbase_defs.h', '\tstruct rockchip_opp_info opp_info;\n', G('\tstruct rockchip_opp_info opp_info;\n'))
rep('mali_kbase_core_linux.c', '#include <soc/rockchip/rockchip_opp_select.h>\n', G('#include <soc/rockchip/rockchip_opp_select.h>\n'))

# hrtimer_init + .function = F  ->  hrtimer_setup(t, F, clk, mode)
hr = re.compile(r'hrtimer_init(_on_stack)?\(\s*&([^,]+?),\s*([A-Z_]+),\s*([A-Z_]+)\);')
for p in glob.glob(root + '/**/*.c', recursive=True):
    s = open(p).read(); o = s
    for m in list(hr.finditer(s)):
        t = m.group(2).strip()
        fre = re.compile(r'\n[ \t]*' + re.escape(t) + r'\.function\s*=\s*([^;]+);')
        fm = fre.search(s, m.end())
        if not fm or fm.start() - m.end() > 600: print('NOFUNC', p, t); continue
        f = fm.group(1).strip()
        s = s[:fm.start()] + s[fm.end():]
        s = s.replace(m.group(0), 'hrtimer_setup%s(&%s, %s, %s, %s);' % (m.group(1) or '', t, f, m.group(3), m.group(4)), 1)
    if s != o: open(p, 'w').write(s); print('hrtimer', os.path.relpath(p, root))

for p in glob.glob(root + '/**/*.[ch]', recursive=True):
    s = open(p).read(); o = s
    s = re.sub(r'\bdel_timer_sync\(', 'timer_delete_sync(', s)
    s = re.sub(r'\bdel_timer\(', 'timer_delete(', s)
    s = re.sub(r'\bno_llseek\b', 'noop_llseek', s)
    s = re.sub(r'\bfrom_timer\(', 'timer_container_of(', s)
    if s != o: open(p, 'w').write(s); print('timer/llseek', os.path.relpath(p, root))

rep('mali_kbase_mem.h', '#include <linux/sched/mm.h>', '#include <linux/sched/mm.h>\n#include <linux/vmalloc.h>')
rep('mali_kbase_fence.h', '\treturn dma_fence_signal(katom->dma_fence.fence);', '\tdma_fence_signal(katom->dma_fence.fence);\n\treturn 0;')
rep('device/mali_kbase_device.c', '\tif (kbdev->dev->dma_parms)\n\t\terr = dma_set_max_seg_size(kbdev->dev, UINT_MAX);', '\tif (kbdev->dev->dma_parms)\n\t\tdma_set_max_seg_size(kbdev->dev, UINT_MAX);')
edit('mali_kbase_fence_ops.c', lambda s: re.sub(r',\s*\.fence_value_str = kbase_fence_fence_value_str', '', re.sub(r'\s*\.fence_value_str = kbase_fence_fence_value_str,', '', s)).replace('static void kbase_fence_fence_value_str', 'static void __maybe_unused kbase_fence_fence_value_str'))
rep('mali_kbase_core_linux.c', '\tfilp->f_mode |= FMODE_UNSIGNED_OFFSET;\n', '')
rep('mali_kbase_core_linux.c', 'static const struct file_operations kbase_fops = {\n\t.owner = THIS_MODULE,\n', 'static const struct file_operations kbase_fops = {\n\t.owner = THIS_MODULE,\n\t.fop_flags = FOP_UNSIGNED_OFFSET,\n')
rep('mali_kbase_core_linux.c', 'static int kbase_platform_device_remove(struct platform_device *pdev)\n{\n\tstruct kbase_device *kbdev = to_kbase_device(&pdev->dev);\n\n\tif (!kbdev)\n\t\treturn -ENODEV;\n\n\tkbase_device_term(kbdev);\n\tdev_set_drvdata(kbdev->dev, NULL);\n\tkbase_device_free(kbdev);\n\n\treturn 0;\n}', 'static void kbase_platform_device_remove(struct platform_device *pdev)\n{\n\tstruct kbase_device *kbdev = to_kbase_device(&pdev->dev);\n\n\tif (!kbdev)\n\t\treturn;\n\n\tkbase_device_term(kbdev);\n\tdev_set_drvdata(kbdev->dev, NULL);\n\tkbase_device_free(kbdev);\n}')
rep('backend/gpu/mali_kbase_pm_driver.c', '\thrtimer_init_on_stack(&rtdata.timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);\n\trtdata.timer.function = kbasep_reset_timeout;\n', '\thrtimer_setup_on_stack(&rtdata.timer, kbasep_reset_timeout, CLOCK_MONOTONIC, HRTIMER_MODE_REL);\n')
# Linux 6.17+ dropped __SetPageMovable/__ClearPageMovable (movable_ops per page type).
# Page migration stays compiled out (CONFIG_PAGE_MIGRATION_SUPPORT unset -> kbase_page_migration_enabled = 0),
# so these calls are unreachable; stub them.
rep('mali_kbase_mem_migrate.c', '#if !IS_ENABLED(CONFIG_PAGE_MIGRATION_SUPPORT)\n', '#if !IS_ENABLED(CONFIG_PAGE_MIGRATION_SUPPORT)\n#define __SetPageMovable(p, ops) do { } while (0)\n#define __ClearPageMovable(p) do { } while (0)\n')
# Kbuild no longer honours EXTRA_CFLAGS: pass the -DCONFIG_MALI_* set through KCFLAGS.
edit('Makefile', lambda s: s.replace('EXTRA_CFLAGS="$(EXTRA_CFLAGS)" KBUILD_EXTRA_SYMBOLS', 'KCFLAGS="$(EXTRA_CFLAGS)" KBUILD_EXTRA_SYMBOLS'))
# H616 (sunxi) glue in the generic devicetree platform: deassert the GPU bus reset (RST_BUS_GPU) and turn
# clocks + mali-supply on before runtime PM is marked active (panfrost leaves the reset asserted and the
# clocks gated when it unbinds; the generic glue assumed a powered GPU at probe).
P = 'platform/devicetree/mali_kbase_runtime_pm.c'
rep(P, '#include <linux/regulator/consumer.h>\n', '#include <linux/regulator/consumer.h>\n#include <linux/reset.h>\n')
rep(P, '\tdev_dbg(kbdev->dev, "%s\\n", __func__);\n\n\tpm_runtime_set_autosuspend_delay(kbdev->dev, AUTO_SUSPEND_DELAY);',
       '\tstruct reset_control *rst;\n\n\tdev_dbg(kbdev->dev, "%s\\n", __func__);\n\n'
       '\trst = devm_reset_control_array_get_optional_exclusive(kbdev->dev);\n'
       '\tif (IS_ERR(rst))\n\t\treturn PTR_ERR(rst);\n'
       '\tret = reset_control_deassert(rst);\n\tif (ret)\n\t\treturn ret;\n'
       '\tenable_gpu_power_control(kbdev);\n'
       '\tdev_info(kbdev->dev, "sunxi glue: reset deasserted, %u clocks, %u regulators, core clk %lu Hz\\n",\n'
       '\t\t kbdev->nr_clocks, kbdev->nr_regulators,\n'
       '\t\t kbdev->nr_clocks ? clk_get_rate(kbdev->clocks[0]) : 0UL);\n\n'
       '\tpm_runtime_set_autosuspend_delay(kbdev->dev, AUTO_SUSPEND_DELAY);')
# After a panfrost unbind (and with the 7.x driver core) the runtime-PM usage count can already be 1 at probe;
# the generic glue treated that as fatal. Warn only.
rep(P, '\t\tdev_warn(kbdev->dev, "%s: Device runtime usage count unexpectedly non zero %d",\n\t\t\t __func__, atomic_read(&kbdev->dev->power.usage_count));\n\t\tret = -EINVAL;\n',
       '\t\tdev_warn(kbdev->dev, "%s: Device runtime usage count unexpectedly non zero %d",\n\t\t\t __func__, atomic_read(&kbdev->dev->power.usage_count));\n')
