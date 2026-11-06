# Summary job 53-afbc-wb (TEST)
Kernel (uname -v): #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026 (c38, Image md5 f7fc82bd55173cf0ddd56a15ff9a72d6). Start 2026-11-06 16:31:08, end 16:38:26. Exit 0, no BLOCKED/OOPS. Stock kernel restored (7.3.1-edge-sunxi64 #17), lock released.
fbd_readable: 1 (fbd_state_wrong values are meaningful).

## Verdict: FAIL (AFBC differs) - hevc cases fail check 3; vp9 cases PASS

| case | chk0 | chk1 linear | chk2 AFBC ran | chk3 bit-exact | chk6 kernel |
|---|---|---|---|---|---|
| syn-hevc8 | PASS | PASS (src_md5_ok 24, NV12 mod 0) | PASS (YU08 0x0800000000000061) | FAIL interior_exact 0, interior_mismatches 8657547 | PASS (jobs 96 = done 96) |
| syn-hevc10 | PASS | PASS (P010) | PASS (YU10) | FAIL interior_exact 0, interior_mismatches 8852482 | PASS |
| syn-vp9p0 | PASS | PASS | PASS | PASS interior_exact 24, mismatches 0 | PASS |
| syn-vp9p2 | PASS | PASS | PASS | PASS interior_exact 24, mismatches 0 | PASS |
| syn-hevc8-xr24 | PASS | PASS | PASS | FAIL interior_exact 0, interior_mismatches 8657112 | PASS |

## Check 4 (compare_exact / mismatches / max_dev; edge_dist_hist in results.txt)
- syn-hevc8: 0 / 18389480 / 1023 (interior_max_dev 280)
- syn-hevc10: 0 / 18728709 / 1023 (interior_max_dev 275)
- syn-vp9p0: 0 / 2844406 / 296 (all mismatches within 3 px of chroma tile edge: hist 1080268 1022148 741990 then zeros)
- syn-vp9p2: 0 / 2855512 / 313 (same hist shape)
- syn-hevc8-xr24: 0 / 18381021 / 255 (interior_max_dev 70)
- hevc hist is spread over all 32 distances (mismatches everywhere, ~370k interior px/frame wrong of 371712); vp9 mismatches only at edges.

## Check 5 (real, informational): linear rc / afbc rc / repeat_differ / wrong_buffer_kind / modifier / compare_frames / exact / mismatches / max_dev
- real-hevc10: 0 / 0 / 0 / 0 / YU10 / 12 / 0 / 8503585 / 1023
- real-hevc8: linear rc 1 (wb_error -5 on frames 2, 6, 8; wb_failed_delta 3, wb_jobs 48 vs done 45) / afbc rc 1 / 0 / 0 / YU08 / compare_frames 9 (ref_missing 3) / 0 / 6304163 / 1023
- real-vp9p2: 0 / 0 / 0 / 0 / YU10 / 12 / 0 / 2147762 / 325
- real-vp9p0: 0 / 0 / 0 / 0 / YU08 / 12 / 0 / 2081714 / 332
Check 6 for real-hevc8: wb_failed_delta 3, jobs != done (informational case; dmesg_bad 0, dmesg_iommu 0). All other cases dmesg_bad 0, dmesg_iommu 0, wb_failed_delta 0, no dmesg lines matched.

## FAIL lines (first 10 of grep, per case; full in files/<case>/afbc.txt)
### syn-hevc8
```
RESULT frame 0 cap_md5 060faebf6a34e80beb56855eaa446d07 repeat same fbd_ctl 0xff000015 fence_ms 33.0 19.4
RESULT frame 0 vs_linear mismatches 765657 max_dev 1023 interior_pixels 371712 interior_mismatches 360924 interior_max_dev 275 first 61,0 linear 03bda804 afbc 039da415 first_interior 10,10
RESULT frame 1 cap_md5 3cb7e3589fb0e8ea6a339d7deebdf360 repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.6
RESULT frame 1 vs_linear mismatches 763503 max_dev 1023 interior_pixels 371712 interior_mismatches 359913 interior_max_dev 275 first 61,0 linear 000d6a99 afbc 000d5e91 first_interior 10,10
RESULT frame 2 cap_md5 97610afa3db576187f76b8d0df40d9d2 repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 2 vs_linear mismatches 765603 max_dev 1023 interior_pixels 371712 interior_mismatches 360856 interior_max_dev 275 first 61,0 linear 0a8a03ff afbc 0b19f7ff first_interior 11,10
RESULT frame 3 cap_md5 674dc99f0b4594d164efcecf0465f394 repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.6
RESULT frame 3 vs_linear mismatches 765150 max_dev 1023 interior_pixels 371712 interior_mismatches 360667 interior_max_dev 275 first 61,0 linear 207aada2 afbc 20baa5a6 first_interior 10,10
RESULT frame 4 cap_md5 27c037f3ecfd8ab450de2225619d0b8c repeat same fbd_ctl 0xff000015 fence_ms 33.4 22.1
RESULT frame 4 vs_linear mismatches 766220 max_dev 1023 interior_pixels 371712 interior_mismatches 360958 interior_max_dev 275 first 61,0 linear 1ea8cb9e afbc 1e38d39e first_interior 10,10
DUMP: drwxr-xr-x 2 root root    4096 Nov  6 16:34 .
DUMP: drwxr-xr-x 3 root root    4096 Nov  6 16:34 ..
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:34 f000.afbc.cap
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:34 f000.linear.cap
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:34 f001.afbc.cap
```
### syn-hevc10
```
RESULT frame 0 cap_md5 e76b195f155c5f2636337bbc4dea5fb4 repeat same fbd_ctl 0xff000015 fence_ms 33.0 19.3
RESULT frame 0 vs_linear mismatches 779816 max_dev 1023 interior_pixels 371712 interior_mismatches 368811 interior_max_dev 275 first 61,0 linear 385747ff afbc 38574bf7 first_interior 10,10
RESULT frame 1 cap_md5 cd49bb539b52a62531f19113b57741d3 repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.5
RESULT frame 1 vs_linear mismatches 780429 max_dev 1023 interior_pixels 371712 interior_mismatches 369053 interior_max_dev 275 first 61,0 linear 3ff6430e afbc 3ff65318 first_interior 10,10
RESULT frame 2 cap_md5 41b4f34e8988366ed999cb259a66695f repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.6
RESULT frame 2 vs_linear mismatches 778759 max_dev 1023 interior_pixels 371712 interior_mismatches 368056 interior_max_dev 274 first 61,0 linear 23d8dbff afbc 23f8dfff first_interior 10,10
RESULT frame 3 cap_md5 8ca21aa35db9e020357869723e5524cd repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 3 vs_linear mismatches 780227 max_dev 1023 interior_pixels 371712 interior_mismatches 368979 interior_max_dev 275 first 61,0 linear 15ac1000 afbc 152c1800 first_interior 10,10
RESULT frame 4 cap_md5 e22917c1dcfc1e10c2d7b9672e774eee repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 4 vs_linear mismatches 780625 max_dev 1023 interior_pixels 371712 interior_mismatches 369062 interior_max_dev 275 first 61,0 linear 3ff65abe afbc 3ff66ab1 first_interior 10,10
DUMP: drwxr-xr-x 2 root root    4096 Nov  6 16:35 .
DUMP: drwxr-xr-x 3 root root    4096 Nov  6 16:35 ..
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:35 f000.afbc.cap
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:35 f000.linear.cap
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:35 f001.afbc.cap
```
### syn-hevc8-xr24
```
RESULT frame 0 cap_md5 88bef5437466a7d54fbeafaf9f8973f5 repeat same fbd_ctl 0xff000015 fence_ms 33.0 19.5
RESULT frame 0 vs_linear mismatches 765343 max_dev 255 interior_pixels 371712 interior_mismatches 360924 interior_max_dev 69 first 61,0 linear 000eda01 afbc 000eda05 first_interior 10,10
RESULT frame 1 cap_md5 7d815dc7761ebf2bdad51efa59a8eb4b repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 1 vs_linear mismatches 762865 max_dev 255 interior_pixels 371712 interior_mismatches 359776 interior_max_dev 69 first 61,0 linear 0000d6a6 afbc 0000d5a4 first_interior 10,10
RESULT frame 2 cap_md5 35eefca7ce85528407755284e091ae2d repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 2 vs_linear mismatches 765236 max_dev 255 interior_pixels 371712 interior_mismatches 360853 interior_max_dev 69 first 61,0 linear 002aa0ff afbc 002c9fff first_interior 11,10
RESULT frame 3 cap_md5 7190ce96832b65e2583ee7271c8b8646 repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 3 vs_linear mismatches 764860 max_dev 255 interior_pixels 371712 interior_mismatches 360634 interior_max_dev 69 first 61,0 linear 0081aa68 afbc 0082aa69 first_interior 10,10
RESULT frame 4 cap_md5 33cc7b30d165ae71e3c64c68bd7f241b repeat same fbd_ctl 0xff000015 fence_ms 33.3 22.7
RESULT frame 4 vs_linear mismatches 765951 max_dev 255 interior_pixels 371712 interior_mismatches 360958 interior_max_dev 69 first 61,0 linear 007a8ce7 afbc 00788de7 first_interior 10,10
DUMP: drwxr-xr-x 2 root root    4096 Nov  6 16:36 .
DUMP: drwxr-xr-x 3 root root    4096 Nov  6 16:36 ..
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:36 f000.afbc.cap
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:36 f000.linear.cap
DUMP: -rw-r--r-- 1 root root 3145728 Nov  6 16:36 f001.afbc.cap
```

Results: harness/research/afbc-wb/logs/runner-j53/ (results.txt, runner.log, chunk-*.txt, files/<case>/*.txt). Binary dumps files/*/dump/*.cap kept on host, not committed.
