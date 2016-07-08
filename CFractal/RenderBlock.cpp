#include "stdafx.h"
#include "RenderBlock.h"

RenderBlockStatus RenderBlock::getStatus()
{
	return status;
}

RenderBlock::RenderBlock(Vector2d position, double scale)
{
	this->offset = position;
	this->scale = scale;
	status = rsEMPTY;
}

RenderBlock::RenderBlock()
{
}

RenderBlock::~RenderBlock()
{
}

std::string RenderBlock::toString()
{
	return offset.toString() + " : " + floatToStr(scale);
}
