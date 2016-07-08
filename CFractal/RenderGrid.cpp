#include "stdafx.h"
#include "RenderGrid.h"
#include <math.h>
#include "helper.h"
#include "glHelper.h"


///  ------------------------------------------------------------------
///  RenderNode
///  ------------------------------------------------------------------

// Construct the render node.
RenderNode::RenderNode(RenderGrid *parentGrid, RenderNode *parentNode, Vector2d location, int depth)
{
	this->parentGrid = parentGrid;
	this->parentNode = parentNode;
	lastTapped = 0;
	oldestTap = 0;
	center = location;
	this->depth = depth;
	renderBlock = new RenderBlock(getTopLeft(), 1.0 / getSize());
}

// Destroy the render node and any children recursively.
RenderNode::~RenderNode()
{
	// Release any allocated textures
	/*
	if (renderBlock != NULL && renderBlock.texture) 
		renderBlock->texture->deallocateTexture(true)
	*/
	delete renderBlock;
	delete quad[0][0];
	delete quad[1][0];
	delete quad[0][1];
	delete quad[1][1];

	quad[0][0] = NULL;
}


RenderGrid* RenderNode::getParentGrid()
{
	return parentGrid;
}

// Marks block as tapped with current timestep. Used for garbage collection.
// Parent nodes are also tapped.
void RenderNode::tap()
{
	lastTapped = parentGrid->tickTime;
	if ((oldestTap == 0) || (lastTapped < oldestTap))
		oldestTap = lastTapped;
	if (parentNode)
		parentNode->tap();
}

// Recursively removes and nodes that have not been tapped for given number of seconds.
void RenderNode::garbageCollect(double ageThreshold)
{
	//TRACE("Collecting garbage.");

	// no need to garabage collect if we are all within the time threshold.
	if (oldestTap > parentGrid->tickTime - ageThreshold)
		return;

	// otherwise need will need to check if this block needs to be cleaned up
	if (lastTapped < parentGrid->tickTime - ageThreshold) {

		if (parentNode) {
			parentNode->oldestTap = 0;

			// update parents oldest tap by finding smallest non zero oldest tap of siblings
			for (int u = 0; u < 1; u++)
				for (int v = 0; v < 1; v++)
					if ((parentNode->quad[u][v]->oldestTap != 0) && ((parentNode->quad[u][v]->oldestTap < parentNode->oldestTap) || (parentNode->oldestTap == 0)))
						parentNode->oldestTap = parentNode->quad[u][v]->oldestTap;

			// now we can clear the children nodes.
			// todo: this needs to be cleaned up with the proper destory system.
			delete renderBlock;
			for (int u = 0; u < 1; u++)
				for (int v = 0; v < 1; v++)
				{
					delete quad[u][v];
					quad[u][v] = NULL;
				}
		}
	}
}

Vector2d RenderNode::getTopLeft()
{
	return Vector2d(center.x - getSize() / 2, center.y - getSize() / 2);
}

Vector2d RenderNode::getBottomRight()
{
	return Vector2d(center.x + getSize() / 2, center.y + getSize() / 2);
}

double RenderNode::getSize() 
{
	return 8.0 / std::pow(2, depth);
}

std::string RenderNode::toString()
{	
	return "Node [" + center.toString() + "] (depth:" + intToStr(depth) + ")";	
}

void RenderNode::split()
{
	delete quad[0][0];
	delete quad[1][0];
	delete quad[0][1];
	delete quad[1][1];
	double quarterSize = getSize() / 4;
	quad[0][0] = new RenderNode(parentGrid, this, Vector2d(center.x - quarterSize, center.y - quarterSize), depth + 1);
	quad[1][0] = new RenderNode(parentGrid, this, Vector2d(center.x + quarterSize, center.y - quarterSize), depth + 1);
	quad[0][1] = new RenderNode(parentGrid, this, Vector2d(center.x - quarterSize, center.y + quarterSize), depth + 1);
	quad[1][1] = new RenderNode(parentGrid, this, Vector2d(center.x + quarterSize, center.y + quarterSize), depth + 1);
}


// If this node needs renderering then add this node, and any unrendered parent nodes
// do the render que.  Blocks are rendered from highest priority to lowest.  Priority
// less than zero will never be rendered.  Parent blocks are rendered with double priority.
void RenderNode::addToRenderQue(int priority = 0)
{
	if (renderBlock->getStatus() != rsEMPTY)
		return;

	// recurse to parent nodes.
	if (parentNode)
		parentNode->addToRenderQue(priority * 2);

	renderBlock->priority = priority;
	parentGrid->renderQueue->addJob(renderBlock);
}

// Returns if any part of this node is in view or not.
// Todo: this relates to drawing and probably shouldn't be here.
bool RenderNode::isInView()
{		
	// Old circle method... quiet fast but not always 100 % correct.
	double viewRadius = 512.0;
	double halfSize = getSize() / 2;
	double blockRadius = sqrt(2.0 * halfSize * halfSize) * parentGrid->viewport->scale * 16;
	double dst = distanceFromCenterOfScreen();
	dst -= blockRadius;
	if (dst < 0)
		dst = 0;	
	return dst < (viewRadius);
	
}

// Prepairs block for drawing.  I.e. adds unrendered blocks to render que, adds un-uploaded blocks to upload cue. 
void RenderNode::recursivePrep(int requiredDepth)
{
	// cull any non visible blocks
	if (!isInView())
		return;

	// If we are a trivial block then there is no need to prep our children blocks
	/*
	if (renderBlock.isTrivial)
		return;
	*/

	// Stop and required depth
	if (depth == requiredDepth) 
	{
		prep();
		return;
	} else {
		// Otherwise process this block and all its children.

		prep();

		// Split block if required
		if (!(quad[0][0]))
			split();

		// Prep each child
		if (quad[0][0]) quad[0][0]->recursivePrep(requiredDepth);
		if (quad[1][0]) quad[1][0]->recursivePrep(requiredDepth);
		if (quad[0][1]) quad[0][1]->recursivePrep(requiredDepth);
		if (quad[1][1]) quad[1][1]->recursivePrep(requiredDepth);
	}
}

// Prepaires node by enquing it to be rendered if needed.
void RenderNode::prep()
{
	Assert(renderBlock, "Render block not allocated.");
	//TRACE(toString() + " is being asked to prepare.");
	if (renderBlock->getStatus() == rsEMPTY)
	{		
		addToRenderQue(50);
	}
}

///  ------------------------------------------------------------------
///  RenderGrid
///  ------------------------------------------------------------------

RenderGrid::RenderGrid(Viewport *viewport)
{
	TRACE("Creating render grid (using block size of 64)");
	blockSize = 64;
	root = new RenderNode(this, NULL, Vector2d(0, 0), 0);
	//pageManager = ...
	renderQueue = new RenderQueue();
	this->viewport = viewport;
}


RenderGrid::~RenderGrid()
{
	delete root;	
	delete renderQueue;
}

// Returns node at given location.
// Depth: Recusion level, 0 = top
// Returns node if found otherwise NULL
RenderNode* RenderGrid::getNode(Vector2d location, int depth)
{
	// Check for root
	if (depth == 0)
		return root;

	// Search for node in quad tree.
	RenderNode *currentNode = root;
	while (currentNode->depth < depth)
	{
		// dig down another level
		int u = (location.x < currentNode->center.x) ? 0 : 1;
		int v = (location.y < currentNode->center.y) ? 0 : 1;
		if (!(currentNode->quad[u][v]))
			return NULL;
		currentNode = currentNode->quad[u][v];
	}
	return currentNode;

}

// Draws this node and all its children to the current viewport until required depth is reached.
// Blocks not within the viewport are pruned out.
void RenderNode::recursiveDraw()
{	
	// Cull non visibile blocks.
	if (!isInView())
		return;
	
	// Draw target depth.
	if (depth == parentGrid->targetDepth) {
		draw();
	}
	else {
		// draw children instead
		for (int u = 0; u < 2; u++)
			for (int v = 0; v < 2; v++)
				if (quad[u][v]) quad[u][v]->recursiveDraw();
	}
}

// Draws block as a single color.
void RenderNode::drawDebugBlock(int atX, int atY, double scale, COLORREF color)
{
	if (!parentGrid->viewport->target)
		return;

	auto destination = parentGrid->viewport->target;
	auto block = renderBlock->data;

	int scaledSize = (int)(64 * scale);

	drawRect(destination, Vector2d(atX, atY), Vector2d(atX + scaledSize, atY + scaledSize), color);
}

void RenderNode::draw()
{
	auto fractal_topLeft = Vector2d(center.x - getSize() / 2, center.y - getSize() / 2);
	fractal_topLeft.x *= 16;
	fractal_topLeft.y *= 16;

	double size = getSize();
	double target_size = 64.0 / parentGrid->viewport->scale;

	auto target_topLeft = parentGrid->viewport->toScreen(fractal_topLeft);	
	auto target_bottomRight = Vector2d(target_topLeft.x + 64.0 * 16.0 * size / target_size, target_topLeft.y + 64.0 * 16.0 * size / target_size);


	// for the moment just draw this node, and don't worry about scanning upwards for parent nodes.
	if (renderBlock->status == rsUPLOADED)
	{	
		drawTexture(target_topLeft, target_bottomRight, renderBlock->texture);
	}
	else {

		// look up in the chain for a rendered block
		int blocksUpToCheck = 10;
		auto node = this;
		RenderNode *foundNode = NULL;
		while (blocksUpToCheck > 0 && node->parentNode)
		{
			node = node->parentNode;
			if (node->renderBlock && node->renderBlock->status == rsUPLOADED) {
				foundNode = node;
				break;
			}
		}

		if (foundNode) {
			// use this parent node instead.
			double sectionWidth = this->getSize() / foundNode->getSize();
			double sectionHeight = this->getSize() / foundNode->getSize();
			double sectionX = (foundNode->center.x - this->center.x) / foundNode->getSize() - (sectionWidth / 2);
			double sectionY = (foundNode->center.y - this->center.y) / foundNode->getSize() - (sectionHeight / 2);
			//auto uv1 = Vector2d(foundNode->getTopLeft().x - this->getTopLeft().x / foundNode->getSize(), foundNode->getTopLeft().y - this->getTopLeft().y / foundNode->getSize());
			//auto uv2 = Vector2d(foundNode->getTopLeft().x - this->getBottomRight().x / foundNode->getSize(), foundNode->getTopLeft().y - this->getBottomRight().y / foundNode->getSize());

			//TRACE(uv1.toString());

			while (sectionX < 0) sectionX += 1;
			while (sectionY < 0) sectionY += 1;
			while (sectionX > 1) sectionX -= 1;
			while (sectionY > 1) sectionY -= 1;			

			drawTexture(target_topLeft, target_bottomRight, Vector2d(sectionX,sectionY), Vector2d(sectionX + sectionWidth, sectionY + sectionHeight), foundNode->renderBlock->texture);
			//drawTexture(target_topLeft, target_bottomRight, uv1, uv2, foundNode->renderBlock->texture);
		}
		else {
			// nothing for the moment... draw a colored block to indicate loading in the future.
			drawRect(target_topLeft, target_bottomRight, Color(255, 255, 0));
		}
	}
}

// Returns distance of block from center of screen.
double RenderNode::distanceFromCenterOfScreen()
{	
	auto modifiedCenter = Vector2d(center.x * 16.0, center.y * 16.0);
	auto screenCenter = parentGrid->viewport->toScreen(modifiedCenter);
	return Vector2d(screenCenter.x - parentGrid->viewport->size.x / 2.0, screenCenter.y - parentGrid->viewport->size.y / 2.0).length();
	//return Vector2d(center.x * 8 - parentGrid->viewport->offset.x, center.y * 8 - parentGrid->viewport->offset.y).length()*parentGrid->viewport->scale;
}


// Removes nodes until the cache usage level reaches below cacheSizeMB (in megabytes)
void RenderGrid::garbageCollect()
{
	// NIY:
	return;
}

// Returns render block at given location and depth, or NULL if none exists.
RenderBlock* RenderGrid::getBlock(Vector2d location, int depth)
{
	RenderNode *node = getNode(location, depth);
	if (node)
		return node->renderBlock;
	else
		return NULL;
}

// Creates a block at given location and depth.  Parent nodes are created as required.
// If the block already exists nothing is changed.
void RenderGrid::createBlock(Vector2d location, int depth)
{
	// Check if block already exists.
	if (getBlock(location, depth))
		return;

	// look for closest level match.
	int currentDepth = 0;

	while (getBlock(location, currentDepth))
		currentDepth++;

	// go back to previous existing block
	currentDepth--;

	// then split this block until we get to the desired level.
	while (currentDepth <= depth - 1)
	{
		getNode(location, depth)->split();
		currentDepth++;
	}

}

// Prepairs all visibile blocks according to current viewport.
void RenderGrid::prepare(int depth)
{
	if (depth < 1) depth = 1;
	root->recursivePrep(depth);
}

///  ------------------------------------------------------------------
///  Viewport
///  ------------------------------------------------------------------

// Converts from viewport space to screen space.
Vector2d Viewport::toScreen(Vector2d viewportLocation)
{
	Vector2d vec = Vector2d();
	vec.x = ((viewportLocation.x - offset.x) * scale) + (size.x / 2);
	vec.y = ((viewportLocation.y - offset.y) * scale) + (size.y / 2);
	return vec;
}

// Converts from screen space to viewport space.
Vector2d Viewport::toViewport(Vector2d screenLocation)
{
	Vector2d vec = Vector2d();
	vec.x = (screenLocation.x - (size.x / 2)) / scale + offset.x;
	vec.y = (screenLocation.y - (size.y / 2)) / scale + offset.y;
	return vec;
}

// Clips screen space rectangle co-ords to visible viewport
void Viewport::clip(Vector2d * topLeft, Vector2d * bottomRight)
{
	topLeft->x = topLeft->x < 0 ? 0 : topLeft->x;
	topLeft->y = topLeft->y < 0 ? 0 : topLeft->y;
	bottomRight->x = bottomRight->x > size.x ? size.x: bottomRight->x;
	bottomRight->y = bottomRight->y > size.y ? size.y : bottomRight->y;
}

Viewport::Viewport()
{
	offset = Vector2d(0, 0);
	scale = 1.0;
	size = Vector2d(640, 640);
	target = 0;
}

Viewport::~Viewport()
{
}
