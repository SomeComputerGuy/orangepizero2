# Job 39-ve-encoder summary
Kernel (uname -v): #31 SMP PREEMPT Fri Nov  6 08:21:32 UTC 2026 (encoder registered as /dev/video1); stock restored 7.3.1-edge-sunxi64 #17. End 2026-11-06 08:41:41. Exit 0. No OOPS/BLOCKED/stall.
State: venc 
Results: harness/research/ve-encoder/logs/runner-venc/ (results.txt, runner.log, files/venc/)

## all-run values
venc all encoder_node 1
venc all probe_registered 1
venc all controls 20
venc all boot_warnings 0
venc all media_node /dev/media0
venc all media_info 1
venc all dec_D_rc 0
venc all media /dev/media0 model=cedrus
venc all media /dev/media1 model=sun50i-di300
venc all compliance_failed 1
venc all compliance_warnings 0
venc all compliance_unexpected 0
venc all compliance_dec_fail 1
venc all dmesg_bad 0
venc all dmesg_iommu 0
venc all dmesg_timeout 0
venc all dmesg_encode_failed 0

## Per run (key=value from results.txt)
- r1: frames=30 bytes=994139 keyframes=30 errors=0 ret=0 avg_us=3234 max_us=3300 fps=17.2 rc=0 stream_bytes=994139 head_hex=000000016742c028965402802dd080000003008000001e420000000168ce3c30 start_first=1 start_codes=90 nal_sps=30 nal_pps=30 nal_idr=30 nal_p=0 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=1402880 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=30 hwdec_md5_ffmpeg=06bebbe3801c36631cd02f407f7daeb3 psnr_avg=49.20 psnr_min=49.11 psnr_frames=30 hwdec_frames=30 hwdec_md5=06bebbe3801c36631cd02f407f7daeb3 hwdec_md5_match=1 
- r2: frames=30 bytes=653763 keyframes=3 errors=0 ret=0 avg_us=3180 max_us=3255 fps=156.3 rc=0 stream_bytes=653763 head_hex=000000016742c028965402802dd080000003008000001e420000000168ce3c30 start_first=1 start_codes=36 nal_sps=3 nal_pps=3 nal_idr=3 nal_p=27 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=1402880 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=30 hwdec_md5_ffmpeg=6383b2fd91091add1525584e1f392d8f psnr_avg=47.64 psnr_min=47.42 psnr_frames=30 hwdec_frames=30 hwdec_md5=6383b2fd91091add1525584e1f392d8f hwdec_md5_match=1 
- r3: frames=10 bytes=870745 keyframes=10 errors=0 ret=0 avg_us=7091 max_us=7168 fps=7.6 rc=0 stream_bytes=870745 head_hex=000000016742c028965403c0113f2c20000003002000000790800000000168ce start_first=1 start_codes=30 nal_sps=10 nal_pps=10 nal_idr=10 nal_p=0 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=3164160 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=10 hwdec_md5_ffmpeg=e1124dbf908d389de8b4ed7bd9671d7b psnr_avg=53.86 psnr_min=53.77 psnr_frames=10 hwdec_frames=10 hwdec_md5=e1124dbf908d389de8b4ed7bd9671d7b hwdec_md5_match=1 
- r4: frames=10 bytes=326899 keyframes=1 errors=0 ret=0 avg_us=6807 max_us=6829 fps=72.3 rc=0 stream_bytes=326899 head_hex=000000016742c028965403c0113f2c20000003002000000790800000000168ce start_first=1 start_codes=12 nal_sps=1 nal_pps=1 nal_idr=1 nal_p=9 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=3164160 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=10 hwdec_md5_ffmpeg=0f61ca51068603ab793356437c654c54 psnr_avg=44.46 psnr_min=44.29 psnr_frames=10 hwdec_frames=10 hwdec_md5=0f61ca51068603ab793356437c654c54 hwdec_md5_match=1 
- r5: frames=5 bytes=185700 keyframes=5 errors=0 ret=0 avg_us=3678 max_us=3720 fps=14.4 rc=0 stream_bytes=185700 head_hex=000000016742c028965402b030f37080000003008000001e420000000168ce3c start_first=1 start_codes=15 nal_sps=5 nal_pps=5 nal_idr=5 nal_p=0 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=1607168 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=5 hwdec_md5_ffmpeg=edcc1ec6d7c826e79d200bc5a1a83537 psnr_avg=49.15 psnr_min=49.08 psnr_frames=5 hwdec_frames=5 hwdec_md5=edcc1ec6d7c826e79d200bc5a1a83537 hwdec_md5_match=1 
- r6: frames=10 bytes=94948 keyframes=2 errors=0 ret=0 avg_us=1360 max_us=1441 fps=43.9 rc=0 stream_bytes=94948 head_hex=000000016742c028965405a1ed08000003000800000301e4200000000168ce3c start_first=1 start_codes=14 nal_sps=2 nal_pps=2 nal_idr=2 nal_p=8 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=529920 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=10 hwdec_md5_ffmpeg=3c4385f68182a8e97a07a108efdb9447 psnr_avg=47.46 psnr_min=47.09 psnr_frames=10 hwdec_frames=10 hwdec_md5=3c4385f68182a8e97a07a108efdb9447 hwdec_md5_match=1 
- r7: frames=10 bytes=110376 keyframes=2 errors=0 ret=0 avg_us=1576 max_us=1604 fps=37.4 rc=0 stream_bytes=110376 head_hex=000000016742c028965406c1ef3708000003000800000301e4200000000168ce start_first=1 start_codes=14 nal_sps=2 nal_pps=2 nal_idr=2 nal_p=8 sps_ref_idc=3 dmesg_iommu=0 buffers_file=4 source_bytes=635904 buffers_format=1 source_room=1 dmesg_timeout=0 ffmpeg_errors=0 decoded=10 hwdec_md5_ffmpeg=770fe67c3ad9ac7ead8f8fa66e2d9b5d psnr_avg=47.58 psnr_min=47.15 psnr_frames=10 hwdec_frames=10 hwdec_md5=770fe67c3ad9ac7ead8f8fa66e2d9b5d hwdec_md5_match=1 

Checks 1-9: all PASS for r1-r7 (rc 0, errors 0, frames/keyframes as expected, ffmpeg_errors 0, decoded=frames, PSNR 44-54 dB, hwdec md5 match 1, framing ok, dmesg_* 0, buffers_format 1, source_room 1).
r5 HWDEC: raw 7879680 crop frames 5 stride 1368 rest 0; r7 HWDEC: raw 6163200 crop frames 10 stride 856 rest 0.
dmesg: dmesg_bad/iommu/timeout/encode_failed all 0; nothing abnormal.
