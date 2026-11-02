/* SPDX-License-Identifier: Apache-2.0 */
/*
 * AVS2 weighting quantization tables (GB/T 33475.2 / IEEE 1857.4).
 *
 * Copied from Rockchip MPP, mpp/codec/dec/avs2/avs2d_ps.c at commit
 * 7916c3cc000fefc0bdf96636b7d54fe174724f44:
 * Copyright 2021 Rockchip Electronics Co. LTD
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License. You may obtain
 * a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.
 *
 * Changes: types and names; only the tables are kept. The same values are
 * in davs2 and in the Allwinner libawavs2.so, including the default 8x8
 * entry [3][7] = 28, which the Amlogic driver has as 112 (see
 * harness/research/avs2/syntax.md section 7).
 */
#ifndef AVS2_WQ_TABLES_H
#define AVS2_WQ_TABLES_H

#include <stdint.h>

#define AVS2_WQ_UNDETAILED	0
#define AVS2_WQ_DETAILED	1

static const uint8_t avs2_wq_param_default[2][6] = {
	{ 67, 71, 71, 80, 80, 106 },
	{ 64, 49, 53, 58, 58, 64 },
};

static const uint8_t avs2_wq_default_4x4[16] = {
	64, 64, 64, 68,
	64, 64, 68, 72,
	64, 68, 76, 80,
	72, 76, 84, 96,
};

static const uint8_t avs2_wq_default_8x8[64] = {
	64, 64, 64, 64, 68, 68, 72, 76,
	64, 64, 64, 68, 72, 76, 84, 92,
	64, 64, 68, 72, 76, 80, 88, 100,
	64, 68, 72, 80, 84, 92, 100, 28,
	68, 72, 80, 84, 92, 104, 112, 128,
	76, 80, 84, 92, 104, 116, 132, 152,
	96, 100, 104, 116, 124, 140, 164, 188,
	104, 108, 116, 128, 152, 172, 192, 216,
};

static const uint8_t avs2_wq_model_8x8[4][64] = {
	{
		0, 0, 0, 4, 4, 4, 5, 5,
		0, 0, 3, 3, 3, 3, 5, 5,
		0, 3, 2, 2, 1, 1, 5, 5,
		4, 3, 2, 2, 1, 5, 5, 5,
		4, 3, 1, 1, 5, 5, 5, 5,
		4, 3, 1, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
	}, {
		0, 0, 0, 4, 4, 4, 5, 5,
		0, 0, 4, 4, 4, 4, 5, 5,
		0, 3, 2, 2, 2, 1, 5, 5,
		3, 3, 2, 2, 1, 5, 5, 5,
		3, 3, 2, 1, 5, 5, 5, 5,
		3, 3, 1, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
	}, {
		0, 0, 0, 4, 4, 3, 5, 5,
		0, 0, 4, 4, 3, 2, 5, 5,
		0, 4, 4, 3, 2, 1, 5, 5,
		4, 4, 3, 2, 1, 5, 5, 5,
		4, 3, 2, 1, 5, 5, 5, 5,
		3, 2, 1, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
	}, {
		0, 0, 0, 3, 2, 1, 5, 5,
		0, 0, 4, 3, 2, 1, 5, 5,
		0, 4, 4, 3, 2, 1, 5, 5,
		3, 3, 3, 3, 2, 5, 5, 5,
		2, 2, 2, 2, 5, 5, 5, 5,
		1, 1, 1, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
		5, 5, 5, 5, 5, 5, 5, 5,
	},
};

static const uint8_t avs2_wq_model_4x4[4][16] = {
	{ 0, 4, 3, 5, 4, 2, 1, 5, 3, 1, 1, 5, 5, 5, 5, 5 },
	{ 0, 4, 4, 5, 3, 2, 2, 5, 3, 2, 1, 5, 5, 5, 5, 5 },
	{ 0, 4, 3, 5, 4, 3, 2, 5, 3, 2, 1, 5, 5, 5, 5, 5 },
	{ 0, 3, 1, 5, 3, 4, 2, 5, 1, 2, 2, 5, 5, 5, 5, 5 },
};

#endif
