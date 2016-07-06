#pragma once

/** Defines a block of fractal points to calculate */
struct FractalBlock {
	int width;
	int height;
	float *x_in;
	float *y_in;
	int *values_out;
};

/// A block within the fractal that has 4 children blocks (that may or may not be rendered). 
///
class QuadBlock {
public:
	QuadBlock *children[2][2];
};

/// Produces solutions to the mandelbrot set 
///
class MandelbrotSolver {

	// different solvers require different block sizes.
private:
	int block_size = 64;
	float threshold = 2.0f;
	
	/// Simple mandelbrot solver, just written in c++
	void simple_solve(FractalBlock block);	
	void intrinsic_solve(FractalBlock block);	
	void SSE_solve(FractalBlock block);

public:
	// Creates a fractal block with locations to be rendered. 
	FractalBlock CreateBlock(float x, float y, float scale);

	void Solve(FractalBlock block) { intrinsic_solve(block); }

};