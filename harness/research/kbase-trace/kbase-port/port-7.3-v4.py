#!/usr/bin/env python3
# port-7.3.py v4 block (after runner job 65). Run alone on an already-ported tree: python3 port-7.3-v4.py <bifrost dir>
# (port-7.3.py also runs it at its end, for a fresh tree). Load/unload noise that is ours (the port/glue), no behaviour
# change for the GPU:
#  1. "error -ENXIO: IRQ JOB/MMU/GPU not found": get_irqs() tries the upper-case names first with platform_get_irq_byname(),
#     which logs an error when the name is missing; the H616 DT names them job/mmu/gpu (lower case, the binding's names),
#     so the fallback always succeeds. Use the _optional variant for the first (upper-case) attempt.
#  2. "workqueue: mali_mmu0 is using neither WQ_PERCPU or WQ_UNBOUND" WARNING (7.x): per-CPU was the old default, so
#     pass WQ_PERCPU explicitly where neither flag is given (the kernel sets the same flag after the WARN_ONCE).
#  3. Unload: "unbalanced disables for <supply>" (_regulator_disable WARNING) + WARN_ON in disable_gpu_power_control():
#     the generic glue enables a regulator/clock only if it is not already on (regulator_is_enabled()/__clk_is_enabled()
#     look at the hardware, not at this consumer), and disables it whenever it is on. The GPU supply on the Zero2 is
#     already on (shared/boot-on), so kbase never took its own reference and the disable at term was unbalanced. Track
#     this consumer's own enables in a bitmask and disable only what kbase enabled.
import os, sys
if 'rep' not in globals():
    root = sys.argv[1]
    def edit(path, fn):
        p = os.path.join(root, path); s = open(p).read(); n = fn(s)
        if n != s: open(p, 'w').write(n); print('patched', path)
    def rep(path, a, b, count=1):
        def f(s):
            if a not in s: print('MISSING in', path, ':', a[:60]); return s
            return s.replace(a, b, count)
        edit(path, f)

rep('mali_kbase_core_linux.c', '\t\tirq = platform_get_irq_byname(pdev, irq_names_caps[i]);\n',
    '\t\tirq = platform_get_irq_byname_optional(pdev, irq_names_caps[i]);\n')

rep('mmu/backend/mali_kbase_mmu_jm.c', 'alloc_workqueue("mali_mmu%u", 0, 0, i);', 'alloc_workqueue("mali_mmu%u", WQ_PERCPU, 0, i);')
rep('backend/gpu/mali_kbase_jm_hw.c', 'alloc_workqueue("Mali reset workqueue", 0, 1);', 'alloc_workqueue("Mali reset workqueue", WQ_PERCPU, 1);')
rep('mali_kbase_event.c', 'alloc_workqueue("kbase_event", WQ_MEM_RECLAIM, 1);', 'alloc_workqueue("kbase_event", WQ_MEM_RECLAIM | WQ_PERCPU, 1);')
rep('mali_kbase_debug_job_fault.c', 'alloc_workqueue("kbase_job_fault_resume_work_queue", WQ_MEM_RECLAIM, 1);',
    'alloc_workqueue("kbase_job_fault_resume_work_queue", WQ_MEM_RECLAIM | WQ_PERCPU, 1);')

P = 'platform/devicetree/mali_kbase_runtime_pm.c'
rep(P, 'static struct reset_control *sunxi_gpu_rst;\n',
    'static struct reset_control *sunxi_gpu_rst;\n'
    '/* sunxi: regulators/clocks this driver enabled itself (bit i = regulators[i] / clocks[i]); see port-7.3-v4.py */\n'
    'static unsigned long sunxi_reg_on, sunxi_clk_on;\n')
rep(P, '\t\telse if (!regulator_is_enabled(kbdev->regulators[i]))\n\t\t\tWARN_ON(regulator_enable(kbdev->regulators[i]));\n',
    '\t\telse if (!(sunxi_reg_on & BIT(i)) && !WARN_ON(regulator_enable(kbdev->regulators[i])))\n'
    '\t\t\tsunxi_reg_on |= BIT(i);\n')
rep(P, '\t\telse if (!__clk_is_enabled(kbdev->clocks[i]))\n\t\t\tWARN_ON(clk_prepare_enable(kbdev->clocks[i]));\n',
    '\t\telse if (!(sunxi_clk_on & BIT(i)) && !WARN_ON(clk_prepare_enable(kbdev->clocks[i])))\n'
    '\t\t\tsunxi_clk_on |= BIT(i);\n')
rep(P, '\t\telse if (__clk_is_enabled(kbdev->clocks[i])) {\n\t\t\tclk_disable_unprepare(kbdev->clocks[i]);\n\t\t\tWARN_ON(__clk_is_enabled(kbdev->clocks[i]));\n\t\t}\n',
    '\t\telse if (sunxi_clk_on & BIT(i)) {\n\t\t\tclk_disable_unprepare(kbdev->clocks[i]);\n\t\t\tsunxi_clk_on &= ~BIT(i);\n\t\t}\n')
rep(P, '\t\telse if (regulator_is_enabled(kbdev->regulators[i]))\n\t\t\tWARN_ON(regulator_disable(kbdev->regulators[i]));\n',
    '\t\telse if ((sunxi_reg_on & BIT(i)) && !WARN_ON(regulator_disable(kbdev->regulators[i])))\n'
    '\t\t\tsunxi_reg_on &= ~BIT(i);\n')
