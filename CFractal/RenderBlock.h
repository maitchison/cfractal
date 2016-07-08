#pragma once

#include "helper.h"
#include "glHelper.h"
#include "Mandel.h"

enum RenderBlockStatus {
	// No rendered fractal data, page will be null.
	rsEMPTY,
	// Block is in que to be rendered.
	rsINQUE,
	// Block is currently being rendered[renderPage allocated]
	rsRENDERING,
	// Block has been rendered but is not uploaded to a texture
	rsRENDERED,
	// Block is currently being uploaded to video card[renderPage.texture initilized]
	rsUPLOADING,
	// Block has been uploaded to video card and pages texture is active
	rsUPLOADED
};

class RenderBlock
{
private:
public:

	Vector2d offset;
	double scale;

	// If block contains all the same color then this will be true.
	bool isTrivial = false;

	FractalBlock data;

	Texture texture;

	RenderBlockStatus status;
	int priority;
	RenderBlockStatus getStatus();
	RenderBlock(Vector2d position, double scale);

	RenderBlock();
	~RenderBlock();

	std::string toString();
};

