// Solver for Mandelbrot set
//
// Date: 2016/06/27

#include "stdafx.h"
#include "Mandel.h"
#include "xmmintrin.h"

FractalBlock MandelbrotSolver::CreateBlock(float x, float y, float scale)
	{
		FractalBlock result;
		result.width = block_size;
		result.height = block_size;
		result.x_in = new float[block_size*block_size];
		result.y_in = new float[block_size*block_size];
		result.values_out = new int[block_size*block_size];
		for (int xlp = 0; xlp < block_size; xlp++)
		{
			for (int ylp = 0; ylp < block_size; ylp++)
			{
				result.x_in[xlp + ylp * block_size] = x + (float)xlp * scale;
				result.y_in[xlp + ylp * block_size] = y + (float)ylp * scale;
			}
		}
		return result;
	}

/// Simple mandelbrot solver, just written in c++
void MandelbrotSolver::simple_solve(FractalBlock block)
	{
		int length = block.width * block.height;

		double thresholdSquared = threshold * threshold;			

		int index = 0;

		for (int i = 0; i < length; i++) 
		{
			double c = block.x_in[i];
			double ci = block.y_in[i];

			double z = 0;
			double zi = 0;

			int it = 0;
			for (int j = 0; j < 1000; j++)
			{
				it ++;
				// z = z*z + c
				double _z = z * z - zi * zi;
				double _zi = 2 * z * zi;
				z = _z + c;
				zi = _zi + ci;
				// check length of z
				if (z*z + zi*zi > thresholdSquared) {
					break;
				}
			}

			block.values_out[index] = it;
			index++;

		}
	}

/// SIMD solver, uses SSE.
void MandelbrotSolver::intrinsic_solve(FractalBlock block)
{	

	int length = block.width * block.height;

	float thresholdSquared = threshold * threshold;
	
	int index = 0;	

	for (int i = 0; i < length/4; i++)
	{
		// pack into a 4 vector		

		__m128 c = _mm_set_ps(block.x_in[index], block.x_in[index + 1], block.x_in[index + 2], block.x_in[index + 3]);
		__m128 ci = _mm_set_ps(block.y_in[index], block.y_in[index + 1], block.y_in[index + 2], block.y_in[index + 3]);

		__m128 z = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);
		__m128 zi = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);
		
		__m128 _z = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);
		__m128 _zi = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);

		__m128 marker = _mm_set_ps(1.0f, 1.0f, 1.0f, 1.0f);
		__m128 counter = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);

		__m128 limit = _mm_set_ps(thresholdSquared, thresholdSquared, thresholdSquared, thresholdSquared);

		for (int j = 0; j < 1000; j++)
		{			
			__m128 _z2 = _mm_mul_ps(z, z);
			__m128 _zi2 = _mm_mul_ps(zi, zi);
			_z = _mm_sub_ps(_z2, _zi2);
			_zi = _mm_mul_ps(z, zi);
			_zi =  _mm_add_ps(_zi, _zi);
			z = _mm_add_ps(_z, c);
			zi = _mm_add_ps(_zi, ci);

			__m128 late_check = _mm_add_ps(_z2, _zi2);

			__m128 mask = _mm_cmple_ps(late_check, limit);
			marker = _mm_and_ps(marker, mask);
			counter = _mm_add_ps(counter, marker);
						
			if (marker.m128_u64[0] == 0 && marker.m128_u64[1] == 0)
				break;			
		}
		

		for (int k = 0; k < 4; k++) {
			block.values_out[index++] = (int)counter.m128_f32[3-k];					
		}
	}
}

void MandelbrotSolver::SSE_solve(FractalBlock block)
{
	int length = block.width * block.height;

	float thresholdSquared = threshold * threshold;

	int index = 0;

	for (int i = 0; i < length / 4; i++)
	{
		// pack into a 4 vector		

		__m128 c = _mm_set_ps(block.x_in[index], block.x_in[index + 1], block.x_in[index + 2], block.x_in[index + 3]);
		__m128 ci = _mm_set_ps(block.y_in[index], block.y_in[index + 1], block.y_in[index + 2], block.y_in[index + 3]);

		__m128 z = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);
		__m128 zi = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);

		__m128 _z = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);
		__m128 _zi = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);

		__m128 marker = _mm_set_ps(1.0f, 1.0f, 1.0f, 1.0f);
		__m128 counter = _mm_set_ps(0.0f, 0.0f, 0.0f, 0.0f);

		__m128 limit = _mm_set_ps(thresholdSquared, thresholdSquared, thresholdSquared, thresholdSquared);

		__asm 
		{
			// setup: 
			// xmm0		c
			// xmm1		ci


			// loop:
			mov			cx, 1000
			_LOOP:			
			
			dec         cx
			jnz         _LOOP
			/*

		//__m128 _z2 = _mm_mul_ps(z, z);
			movaps      xmm0, xmmword ptr[ebp - 90h]
			mulps       xmm0, xmmword ptr[ebp - 90h]
			movaps      xmmword ptr[ebp - 570h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 570h]
			movaps      xmmword ptr[ebp - 180h], xmm0
		//__m128 _zi2 = _mm_mul_ps(zi, zi);
			movaps      xmm0, xmmword ptr[ebp - 0B0h]
			mulps       xmm0, xmmword ptr[ebp - 0B0h]
			movaps      xmmword ptr[ebp - 590h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 590h]
			movaps      xmmword ptr[ebp - 1A0h], xmm0
		// _z = _mm_sub_ps(_z2, _zi2);
			movaps      xmm0, xmmword ptr[ebp - 180h]
			subps       xmm0, xmmword ptr[ebp - 1A0h]
			movaps      xmmword ptr[ebp - 5B0h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 5B0h]
			movaps      xmmword ptr[ebp - 0D0h], xmm0
		// _zi = _mm_mul_ps(z, zi);
			movaps      xmm0, xmmword ptr[ebp - 90h]
			mulps       xmm0, xmmword ptr[ebp - 0B0h]
			movaps      xmmword ptr[ebp - 5D0h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 5D0h]
			movaps      xmmword ptr[ebp - 0F0h], xmm0
		// _zi = _mm_add_ps(_zi, _zi);
			movaps      xmm0, xmmword ptr[ebp - 0F0h]
			addps       xmm0, xmmword ptr[ebp - 0F0h]
			movaps      xmmword ptr[ebp - 5F0h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 5F0h]
			movaps      xmmword ptr[ebp - 0F0h], xmm0
		// z = _mm_add_ps(_z, c);
			movaps      xmm0, xmmword ptr[ebp - 0D0h]
			addps       xmm0, xmmword ptr[ebp - 50h]
			movaps      xmmword ptr[ebp - 610h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 610h]
			movaps      xmmword ptr[ebp - 90h], xmm0
		// zi = _mm_add_ps(_zi, ci);
			movaps      xmm0, xmmword ptr[ebp - 0F0h]
			addps       xmm0, xmmword ptr[ebp - 70h]
			movaps      xmmword ptr[ebp - 630h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 630h]
			movaps      xmmword ptr[ebp - 0B0h], xmm0

		// __m128 late_check = _mm_add_ps(_z2, _zi2);
			movaps      xmm0, xmmword ptr[ebp - 180h]
			addps       xmm0, xmmword ptr[ebp - 1A0h]
			movaps      xmmword ptr[ebp - 650h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 650h]
			movaps      xmmword ptr[ebp - 1C0h], xmm0

		// __m128 mask = _mm_cmple_ps(late_check, limit);
			movaps      xmm0, xmmword ptr[ebp - 1C0h]
			cmpleps     xmm0, xmmword ptr[ebp - 150h]
			movaps      xmmword ptr[ebp - 670h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 670h]
			movaps      xmmword ptr[ebp - 1E0h], xmm0
		// marker = _mm_and_ps(marker, mask);
			movaps      xmm0, xmmword ptr[ebp - 110h]
			andps       xmm0, xmmword ptr[ebp - 1E0h]
			movaps      xmmword ptr[ebp - 690h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 690h]
			movaps      xmmword ptr[ebp - 110h], xmm0
		// counter = _mm_add_ps(counter, marker);
			movaps      xmm0, xmmword ptr[ebp - 130h]
			addps       xmm0, xmmword ptr[ebp - 110h]
			movaps      xmmword ptr[ebp - 6B0h], xmm0
			movaps      xmm0, xmmword ptr[ebp - 6B0h]
			movaps      xmmword ptr[ebp - 130h], xmm0

		// if (marker.m128_u64[0] == 0 && marker.m128_u64[1] == 0)
			mov         eax, 8
			imul        ecx, eax, 0
			mov         dword ptr[ebp - 6B8h], ecx
			*/
		// if (marker.m128_u64[0] == 0 && marker.m128_u64[1] == 0)
				/*
					008FC99D  mov         edx, dword ptr[ebp - 6B8h]
					008FC9A3  mov         eax, dword ptr[ebp - 6B8h]
					008FC9A9  mov         ecx, dword ptr[ebp + edx - 110h]
					008FC9B0 or ecx, dword ptr[ebp + eax - 10Ch]
					008FC9B7  jne         MandelbrotSolver::intrinsicSSE_solve + 3C5h(08FC9E5h)
						008FC9B9  mov         eax, 8
						008FC9BE  shl         eax, 0
						008FC9C1  mov         dword ptr[ebp - 6B8h], eax
						008FC9C7  mov         ecx, dword ptr[ebp - 6B8h]
						008FC9CD  mov         edx, dword ptr[ebp - 6B8h]
						008FC9D3  mov         eax, dword ptr[ebp + ecx - 110h]
						008FC9DA or eax, dword ptr[ebp + edx - 10Ch]
						008FC9E1  jne         MandelbrotSolver::intrinsicSSE_solve + 3C5h(08FC9E5h)
							break;
		008FC9E3  jmp         MandelbrotSolver::intrinsicSSE_solve + 3CAh(08FC9EAh)
	}
	008FC9E5  jmp         MandelbrotSolver::intrinsicSSE_solve + 1D4h(08FC7F4h)
	*/

}


		for (int k = 0; k < 4; k++) {
			block.values_out[index++] = (int)counter.m128_f32[3 - k];
		}
	}	
}

