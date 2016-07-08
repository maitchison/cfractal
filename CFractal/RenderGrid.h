#pragma once

#include <string>
#include "Mandel.h"
#include "helper.h"
#include "glHelper.h"
#include "RenderQueue.h"

class RenderGrid;
class Viewport;

// Node of a quad tree.
class RenderNode
{
private:
	RenderGrid *parentGrid;
	RenderNode *parentNode;	
	
	// Timestamp of the last time this node was tapped (used for GC)
	double lastTapped;

	// Oldest timestamp from this and all child nodes.  Used for efficent GC.
	double oldestTap;

	bool isInView();	
	
public:

	void recursivePrep(int requiredDepth);

	// Data for the node.
	RenderBlock *renderBlock;

	// Children nodes (if any).
	RenderNode *quad[2][2];

	RenderGrid* getParentGrid();

	// Location of nodes center.
	Vector2d center;

	// Depth of node, 0 = top.
	int depth;

	void tap();

	void garbageCollect(double ageThreshold);

	// Returns the top left location of this block in fractal space.
	Vector2d getTopLeft();

	// Returns the bottom right location of this block in fractal space.
	Vector2d getBottomRight();

	// Returns the size in fractal space of this block (i.e. width and height).
	double getSize();

	// Returns a string representation of this block (for debuging).
	std::string toString();

	// Create 4 sub nodes from this node.  Existing nodes will be lost.
	void split();

	void addToRenderQue(int priority);

	// Prepaires node by enquing it to be rendered if needed.
	void prep();

	void recursiveDraw();

	void drawDebugBlock(int atX, int atY, double scale, COLORREF color);

	void drawBlockFast(int atX, int atY, double scale, bool debug);

	void draw();

	double distanceFromCenterOfScreen();	

	RenderNode(RenderGrid *parentGrid, RenderNode *parentNode, Vector2d location, int depth);
	~RenderNode();

};

class RenderGrid
{
private:

public:
	RenderGrid(Viewport *viewport);
	~RenderGrid();

	double tickTime;
	// default block size, normally 64.
	int blockSize;
	// the target depth to draw blocks at
	double targetDepth;
	
	RenderNode* getNode(Vector2d location, int depth);

	// pageManager
	Viewport *viewport;

	RenderQueue *renderQueue;

	// Root node of our quad tree.
	RenderNode* root;

	void garbageCollect();
	RenderBlock* getBlock(Vector2d location, int depth);
	void createBlock(Vector2d location, int depth);	
	void prepare(int depth);	
};

// Used for mapping between a translated and scaled viewport to screen co-ords.
class Viewport
{
public:
	// Viewport offset.  The offset location is the location at the centre of the viewport.
	Vector2d offset;
	// Viewport scale.  
	double scale;
	// size of viewport in pixels
	Vector2d size;

	HBITMAP target;

	Vector2d toScreen(Vector2d viewportLocation);
	Vector2d toViewport(Vector2d screenLocation);

	void clip(Vector2d *topLeft, Vector2d *bottomRight);

	Viewport();
	~Viewport();
};
