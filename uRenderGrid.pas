unit uRenderGrid;

{*****************************************************
tRenderGrid:

The purposes of the tRenderGrid is to handle the rending of
a fractal at various zoom levels.  The fractal subdivided into
4 even squares, each of those squares are then divided again and so on.
This provides a rendering hirachy.  Because each square is
a constant resolution the deeper the level the more quality.

******************************************************}

{todo:
    currently uses vector2d, which is limited to single percision
    this will cause problems at close zooms.  Create an extended
    vector2d class that uses doubles (vector2DEX)
}

{garbage collection:  
 1) manual removal
      User must remove blocks manualy
 2) Time based (TB) cycle oldest tapped
      Blocks are stamped when tapped, the block that was tapped the
      least recent is removed (typicaly user taps blocks when drawn to screen)
 <3 not yet implmeneted>
 3) cycle furthest
      Blocks are removed based on how far away they are from a given point
      this can work well for free exploration
 }


 {

(0,0)
  ---------------------
  |         |         |
  |  Q[0,0] | Q[1,0]  |
  |         |         |
  |---------|---------|
  |         |         |
  |  Q[0,1] | Q[1,1]  |
  |         |         |
  ---------------------
                     (1,1)
  }
interface

uses
    math,
    uMath,
    uDebug,
    uTime,
    uStrings,
    classes,
    uViewPort,
    uColors,
    uPage,
    uPageGLHW,
    uPageManager,
    uVector2d,
    uOpenGL,
    uRenderQue,
    sysUtils;


TYPE
    tRenderGrid = class;

    {2d binary tree node}
    tRenderNode = class
    PRIVATE
        parentGrid: tRenderGrid;
        parentNode: tRenderNode;
        center: tVector2d;          {center of node}
        depth: integer;             {depth of node, 0 = top}
        renderBlock: tRenderBlock;  {data}
        quad: array[0..1,0..1] of tRenderNode; {children (may be unallocated i.e. nil)}
        {timestamp of last time tapped (used for GC)}
        {note: all nodes directly above this node have the same lastTapped value}
        lastTapped: extended;
        {oldest "lastTapped" value for this node or any of its children, used to GC quickly}
        {note all nodes below this node have the same oldestTap value}
        oldestTap: extended;
    PUBLIC
        property getParentGrid: tRenderGrid read parentGrid;
        {garbage collection}
        procedure tap;
        procedure garbageCollect(ageThreshold: single);
        function topLeft: tVector2d;
        function bottomRight: tVector2d;
        function getDrawingCenter: tVector2d;
        function size: extended;
        function halfSize: extended;
        function identify: string;
        function identifyEx: string;
        procedure split;
        function inView: boolean;
        function distanceFromCenterOfScreen: extended;
        procedure addToRenderQue(aPriority: integer = 0);
        procedure recursiveDraw;
        procedure recursivePrep(requiredDepth: integer);
        procedure draw;
        procedure prep;
        constructor create(aParentGrid: tRenderGrid; aParentNode: tRenderNode;aLocation: tVector2d;aDepth: integer);
        destructor Destroy; override;
    end;

    tRenderGrid = class
    PRIVATE
        tickTime: extended;     {set at the start of each .display call to the current time.  Used to tag blocks and perform garbage collection}
        blockSize: integer;     {size to create render blocks, defaults to 64 STUB: not changable at the moment! please un-hardwire this}

        targetDepth: integer;   {the target depth level to draw blocks at}
        depthFactor: single;    {[0..1] based on rounded part of targetDepth}
        targetZoom:  extended;  {target depth to view at; if this is deeper than viewport.scale then res is higher} 

        function getNode(aLocation: tVector2d;aDepth: integer): tRenderNode;
    PUBLIC
        pageManager: tPageManager; {handles allocation of pages}
        renderQue: tRenderQue;  {que used to render blocks}
        viewPort: tViewportGL;
        {primary render node}
        root: tRenderNode;
        procedure garbageCollect(cacheSizeMB: integer);
        {searchs for block at location and depth, if not found returns nil}
        function getBlock(aLocation: tVector2d;aDepth: integer): tRenderBlock;
        {creates block at location and depth, and parent nodes are created as required}
        function createBlock(aLocation: tVector2d;aDepth: integer): tRenderBlock;
        {displays blocks at given zoom level and offset to screen (uses blanks for non rendered sections)}
        procedure display(aTargetZoom: extended);
        {preps all visible blocks}
        procedure prepare(aDepth: integer);
        constructor create;
        destructor Destroy; override;
    end;

implementation

{----------------------------------------------------------}
{ tRenderNode }
{----------------------------------------------------------}


{taps block.  Used for garbage collection.
 A block should be tapped each time its displayed
 Parent nodes are also tapped}
procedure tRenderNode.tap;
begin
    {update last tap}
    lastTapped := parentGrid.tickTime;
    {update oldest tap}
    if (oldestTap = 0) or (lastTapped < oldestTap) then oldestTap := lastTapped;

    if assigned(parentNode) then parentNode.tap;
end;

{if memory usage is high then removes the node that was taped the longest ago}
{note time will be taken from last .display call (using tick time)}
procedure tRenderNode.garbageCollect(ageThreshold: single);
var
    u,v: Integer;
begin
    {strategy 1: remove everything more than "age threshold" seconds old}

    {check oldest tap to see if any nodes under this one need to be GCed}
    if (oldestTap > parentGrid.tickTime-ageThreshold) then begin
        exit;
    end;

    if (lastTapped < parentGrid.tickTime-ageThreshold) then begin

        {update parents oldestTap by finding smallest non zero "oldestTap"}
        if assigned(parentNode) then begin
            parentNode.oldestTap := 0;
            for u := 0 to 1 do for v := 0 to 1 do
                if (parentNode.quad[u,v].oldestTap <> 0) and ((parentNode.quad[u,v].oldestTap < parentNode.oldestTap) or (parentNode.oldestTap = 0)) then
                    parentNode.oldestTap := parentNode.quad[u,v].oldestTap;
        end;

        {clear this node remove and its children}
        renderBlock.release;
        quad[0,0].Free;
        quad[1,0].Free;
        quad[1,1].Free;
        quad[0,1].Free;
        fillchar(quad,sizeof(quad),0);

    end else
        {otherwise check childrens time stamps}
        for u := 0 to 1 do for v := 0 to 1 do
            if assigned(quad[u,v]) then quad[u,v].garbageCollect(ageThreshold);
end;

{returns location of center of block on screen}
function tRenderNode.getDrawingCenter: tVector2d;
begin
    result := parentGrid.viewPort.viewPortToWindow(center.scaled(64));
end;

function tRenderNode.topLeft: tVector2d;
begin
    result := center.translated(vec(-halfSize,-halfSize));
end;

{if this node needs rendering then we add both this node, and any unrendered
 parent nodes to the render cue (starting from root and working down)}
{Blocks are drawn from highest priority to lowest.  Blocks with a pririty < 0
 will never be drawn}
{parent blocks are rendered with double priority}
procedure tRenderNode.addToRenderQue(aPriority: integer = 0);
begin
    {check if block needs rendering}
    if renderBlock.getStatus <> rsEMPTY then exit;
    {recurse to parent nodes}
    if (parentNode <> nil) then parentNode.addToRenderQue(aPriority+100);
    {add us to job}
    renderBlock.priority := aPriority;
    parentGrid.renderQue.addJob(renderBlock);
end;

function tRenderNode.bottomRight: tVector2d;
begin
    result := center.translated(vec(halfSize,halfSize));
end;

{creates render node at location (location is center)}
constructor tRenderNode.create(aParentGrid: tRenderGrid;aParentNode: tRenderNode;aLocation: tVector2d;aDepth: integer);
begin
    parentGrid := aParentGrid;
    parentNode := aParentNode;
    {default taps}
    lastTapped := 0;
    oldestTap := 0;
    {record location and depth}
    center := aLocation;
    depth := aDepth;
    {create render block and define locaiton / scale}
    renderBlock := tRenderBlock.create(aLocation,1/size);
end;

destructor tRenderNode.Destroy;
begin
    {release texture:}
    {note: we first release the texture using the defered method,
     this will speed up the following free call quiet a bit, but
     gl.update must be called at some time to actauly free the memory}
    if assigned(renderBlock) and assigned(renderBlock.texture) then
        renderBlock.texture.deallocateTexture(true);
    renderBlock.free;
    {remove children}
    quad[0,0].Free;
    quad[1,0].Free;
    quad[0,1].Free;
    quad[1,1].Free;
    inherited;
end;

{draws nodes render block to viewport}
{if a node has no graphics data then it uses its parent data (if avaliable)}
procedure tRenderNode.draw;
var
    bp: tBlitParameters;
    searchNode: tRenderNode;
    tc1,tc2: tVector2d; {texture coords}
    drawTL,drawBR: tVector2d; {topleft and bottom right draw locations}
    priority: integer;
const
    DISPLAY_PENDING = false;
    DISPLAY_RENDERING = false;
    DISPLAY_TRIVIAL = false;
    DISPLAY_GRID = false;
begin
    tap;

    {find the best graphics to use (maybe use a parents page if ours is not ready)}
    searchNode := self;
    {while the current node doesn't have any graphics data.. scan upwards}
    while (searchNode <> nil) and (searchNode.renderBlock.getStatus < rsUPLOADED) do begin
        searchNode := searchNode.parentNode;
    end;

    {find blocks drawing location}
    drawTL := getDrawingCenter.translated(vec(-halfSize*parentGrid.viewPort.scale.x,-halfSize*parentGrid.viewPort.scale.x).scaled(64));
    drawBR := getDrawingCenter.translated(vec(+halfSize*parentGrid.viewPort.scale.x,+halfSize*parentGrid.viewPort.scale.x).scaled(64));

    {and draw that page to screen}
    if assigned(searchNode) and (searchNode.renderBlock.getStatus = rsUPLOADED) then begin
        {find subsection of texture to use (only required when using a parents data)}
        tc1 := vDif(searchNode.topLeft,Self.topLeft).scaled(1/searchNode.size);
        tc2 := vDif(searchNode.topLeft,Self.bottomRight).scaled(1/searchNode.size);
        {display block to screen}
        gl.renderParams.clear;
        gl.renderParams.bindTexture(searchNode.renderBlock.texture);
        gl.texturedPoly(
            [vec(drawTL.x,drawTL.y),
             vec(drawBR.x,drawTL.y),
             vec(drawBR.x,drawBR.y),
             vec(drawTL.x,drawBR.y)],
             [tc1,vec(tc2.x,tc1.y),tc2,vec(tc1.x,tc2.y)]);
        {also overlay parent block if:}
        if (
        {...we are on the level that has been requested and...}
        (parentGrid.targetDepth = depth) and 
        {...we are not using a parents texture already and...}
        (searchNode = self) and
        {...parent is rendered}
        assigned(parentNode) and (parentNode.renderBlock.getStatus = rsUPLOADED)
        ) then begin
            {find subsection of texture to use (only required when using a parents data)}
            tc1 := vDif(parentNode.topLeft,Self.topLeft).scaled(1/parentNode.size);
            tc2 := vDif(parentNode.topLeft,Self.bottomRight).scaled(1/parentNode.size);

            gl.renderParams.setBlendMode(bmAlpha);
            gl.renderParams.setDrawColor(rgb(255,255,255,byte(round((1-parentGrid.depthFactor)*255))));
            gl.renderParams.bindTexture(parentNode.renderBlock.texture);
            gl.texturedPoly(
                [vec(drawTL.x,drawTL.y),
                 vec(drawBR.x,drawTL.y),
                 vec(drawBR.x,drawBR.y),
                 vec(drawTL.x,drawBR.y)],
                [tc1,vec(tc2.x,tc1.y),tc2,vec(tc1.x,tc2.y)]);

        end;
    end;

    {draw pending block markers (if enabled)}
    if (DISPLAY_PENDING) and (renderBlock.getStatus = rsINQUE) then begin
        gl.drawColor.setRGB(255,255,0,64);
        gl.bar(drawTL,drawBR);
    end;

    {draw rendering block markers (if enabled)}
    if (DISPLAY_RENDERING) and (renderBlock.getStatus = rsRENDERING) then begin
        gl.drawColor.setRGB(255,0,0,192);
        gl.bar(drawTL,drawBR);
    end;

    {display trivial blocks}
    if (DISPLAY_TRIVIAL) then begin
        if renderBlock.isTrivial then begin
            gl.drawColor.setRGB(0,0,255,64);
            gl.bar(drawTL,drawBR);
        end;
    end;

    {overlay grid (if enabled)}
    if DISPLAY_GRID then begin
        gl.drawColor.setRGB(128,255,128,64);
        gl.rect(drawTL,drawBR);
    end;


end;

{draws this node and all its children to currentViewport until requiredDepth is reached}
{block is displayed using the currently active openGL viewport}
{blocks are pruned out of drawing as soon as an ansestor node is completly
 out of view}
{if a node has no graphics data then it uses its parent data (if avaliable)}
procedure tRenderNode.recursiveDraw;
begin
    {kull any non visible blocks}
    if not inView then
        exit;
    if (depth = parentGrid.targetDepth) then begin
        {we can't draw zero depth objects}
        if depth < 0 then exit;
        draw;
    end else begin
        {if we are a trivial block then draw now at this level and don't worry
         about the children}
        if renderBlock.isTrivial then begin
            draw;
        end else begin
            {draw each child instead}
            if assigned(quad[0,0]) then quad[0,0].recursiveDraw;
            if assigned(quad[1,0]) then quad[1,0].recursiveDraw;
            if assigned(quad[1,1]) then quad[1,1].recursiveDraw;
            if assigned(quad[0,1]) then quad[0,1].recursiveDraw;
        end;
    end;
end;

{prepairs blocks for drawing.  I.e. adds unrended blocks to render cue, adds
 un-uploaded blocks to upload cue}
procedure tRenderNode.recursivePrep(requiredDepth: integer);
begin
    {kull any non visible blocks}
    if not inView then
        exit;

    {if we are a trivial block then there is no need to prep our children blocks}
    if (renderBlock.isTrivial) then 
        exit;

    {if this is the required depth then prep this block stop here}
    if (depth = requiredDepth) then begin
        prep;
        exit;
    end;

    {otherwise lets process this block and its children}
    if true then begin
        {prep this block if it is within 4 levels on the target }
        {(don't wory about anything higher than that}
        if depth > (requiredDepth-4) then
            prep;

        {split block if needed}
        if not assigned(quad[0,0]) then Self.split;

        {prep each child}
        if assigned(quad[0,0]) then quad[0,0].recursivePrep(requiredDepth);
        if assigned(quad[1,0]) then quad[1,0].recursivePrep(requiredDepth);
        if assigned(quad[1,1]) then quad[1,1].recursivePrep(requiredDepth);
        if assigned(quad[0,1]) then quad[0,1].recursivePrep(requiredDepth);
    end;
end;

{returns width of block (calcualted from depth}
function tRenderNode.size: extended;
begin
    result := 8/power(2,depth);
end;

{returns half width of block (calcualted from depth}
function tRenderNode.halfSize: extended;
begin
    result := 4/power(2,depth);
end;

{returns string to identify node (used for debuging}
function tRenderNode.identify: string;
begin
    result := 'Node ['+center.print+'] (depth:'+intToStr(depth)+')';
end;

{returns string to identify node (used for debuging}
function tRenderNode.identifyEx: string;
begin
    result := 'Node ['+center.print+'] (depth:'+intToStr(depth)+') tap='+FloatToStr(lastTapped)+' oldest='+FloatToStr(oldestTap);
end;

{returns distance of block from center of screen (in pixels)}
function tRenderNode.distanceFromCenterOfScreen: extended;
begin
    with parentGrid.viewPort do
        result := vdif(vec(offset.x,offset.y),center.scaled(64)).abs*scale.x;
end;

{returns true if any part of this node is in current view}
{todo: rewrite, use rectangle instead of circle}
function tRenderNode.inView: boolean;
var
    drawPos: tVector2d;
    viewRadius,blockRadius,dst: extended;

    viewPortTopLeft,viewPortBottomRight: tVector2d;
    viewPortSize: extended;
begin

    {old circle method... quiet fast but not always 100% correct}
    with parentGrid.viewPort do begin
        viewRadius := 300;
        blockRadius := sqrt(2*sqr(halfSize))*scale.x*64;
        dst := distanceFromCenterOfScreen;
    end;
    result := dst < (viewRadius+blockRadius);

(*
    {correct method but very slow :(}
    {find viewport corners}
    viewPortSize := 300/parentGrid.viewPort.scale.x/64;
    viewPortTopLeft := vec(parentGrid.viewPort.offset.x/64,parentGrid.viewPort.offset.y/64).translated(vec(-viewPortSize,-viewPortSize));
    viewPortBottomRight := vec(parentGrid.viewPort.offset.x/64,parentGrid.viewPort.offset.y/64).translated(vec(+viewPortSize,+viewPortSize));

    {check if rectangles intersect}
    result := rectanglesIntesect(
        topLeft.x,topLeft.y,bottomRight.x,bottomRight.y,
        viewPortTopLeft.x,viewPortTopLeft.y,viewPortBottomRight.x,viewPortBottomRight.y);
*)

end;

{prepairs block by adding it to the render que}
{if parent nodes are unrendered then they will be also added to the que with a
 higher priority}
procedure tRenderNode.prep;
var
    priority: integer;
begin
    {add this to job que if it is not already there}
    if (renderBlock.getStatus = rsEMPTY) then begin
        priority := round(400-distanceFromCenterOfScreen) div 4;
        if priority > 99 then priority := 99;
        if priority < 1 then priority := 1;
        self.addToRenderQue(priority);
    end;
end;

{create 4 sub nodes from this node, existing nodes will be
 lost}
procedure tRenderNode.split;
begin
    {release and existing child nodes}
    quad[0,0].Free;
    quad[1,0].Free;
    quad[0,1].Free;
    quad[1,1].Free;
    {create 4 new child nodes}
    quad[0,0] := tRenderNode.create(parentGrid,self,vec(center.x-(size/4),center.y-(size/4)),depth+1);
    quad[1,0] := tRenderNode.create(parentGrid,self,vec(center.x+(size/4),center.y-(size/4)),depth+1);
    quad[0,1] := tRenderNode.create(parentGrid,self,vec(center.x-(size/4),center.y+(size/4)),depth+1);
    quad[1,1] := tRenderNode.create(parentGrid,self,vec(center.x+(size/4),center.y+(size/4)),depth+1);
end;

{----------------------------------------------------------}
{ tRenderGrid }
{----------------------------------------------------------}

constructor tRenderGrid.create;
begin
    note(2,'Creating render grid (using block size of 64)');
    blockSize := 64;
    root := tRenderNode.create(self,nil,vec(0,0),0);
    pageManager := tPageManager.create('PM_RenderGrid');
    renderQue := tRenderQue.create(pageManager);
end;

destructor tRenderGrid.Destroy;
begin
    {this will chain destroy all children nodes}
    root.free;
    renderQue.free;
    inherited;
end;

{displays all visible blocks at given zoom to renderGrids viewport}
{depth is calculated by taking log2(zoom)}
{passing viewPort.zoom will give an effective resolution of 64pixels, so you will
 probably want to multiply by some constant}
procedure tRenderGrid.display(aTargetZoom: extended);
begin
    {store zoom}
    targetZoom := aTargetZoom;

    {find depth}
    targetDepth := trunc(log2(targetZoom)); {STUB: change to +0 3.5??}
    depthFactor := sqrt(frac(log2(targetZoom))); {STUB: change to +0 3.5??}
    {note: the sqrt keeps the sharpness a little longer}
    if (targetDepth< 1) then targetDepth:= 1;


    {update tick time}
    tickTime := exactTime;

    assert(assigned(viewport));

    {draw it starting at root}
    root.recursiveDraw;

end;

{returns node at given location
 depth: recusion level, 0 = top, can be as deap as you want
 but >255 is not tested.
 returns: if found returns node, else nil}
{note: depth 0 is always root}
function tRenderGrid.getNode(aLocation: tVector2d;
  aDepth: integer): tRenderNode;
var
    currentNode: tRenderNode;
    u,v: integer;
begin
    result := nil;
    {depth of 0 is root, 1 is roots first quad}
    if (aDepth = 0) then begin
        result := root;
        exit;
    end;

    {search for node}
    currentNode := root;
    while (currentNode.depth < aDepth) do begin
        {dig down another level}
        {otherwise find out which quad we are in}
        if (aLocation.x < currentNode.center.x) then u := 0 else u := 1;
        if (aLocation.y < currentNode.center.y) then v := 0 else v := 1;
        {if quad is unallocated then stop here and return nil}
        if not assigned(currentNode.quad[u,v]) then exit;
        currentNode := currentNode.quad[u,v];
    end;
    result := currentNode;
end;

{prepairs all visibile blocks according to current openGL viewport}
procedure tRenderGrid.prepare(aDepth: integer);
begin
    if (aDepth < 1) then aDepth := 1;
    
    assert(assigned(viewPort));

    root.recursivePrep(aDepth);
end;

{removes nodes until the cache usage level reaches below cacheSizeMB (in megabytes)}
procedure tRenderGrid.garbageCollect(cacheSizeMB: integer);
var
    timeThreshold: single;
    startTime: extended;
begin
    startTime := exactTime;
    if gl.getMemoryUsage > (cacheSizeMB*1024*1024) then begin
        {1. free system memory:}
        timeThreshold := 60*60; {give 60 minute window}
        {remove nodes starting form the oldest and moving to the newest}
        while (timeThreshold > 2) and (gl.getMemoryUsage > (cacheSizeMB*1024*1024)) do begin
            root.garbageCollect(timeThreshold);
            {if we need to try again then reduce the threshold by half}
            timeThreshold := timeThreshold / 2;
        end;
    note(2,'Took '+flt2Str(1000*(exactTime-startTime))+'ms to perform GC');
    end;
end;

function tRenderGrid.getBlock(aLocation: tVector2d;
  aDepth: integer): tRenderBlock;
var
    node: tRenderNode;
begin
    node := getNode(aLocation,aDepth);
    if assigned(node) then
        result := node.renderBlock
    else
        result := nil;
end;


{creates block at location and depth, and parent nodes are created as required}
{if block exists the nothing is changed}
function tRenderGrid.createBlock(aLocation: tVector2d;
  aDepth: integer): tRenderBlock;
var
    currentDepth: integer;
begin
    {check if block already exists}
    if getBlock(aLocation,aDepth) <> nil then exit;
    {look for closest level match}
    currentDepth := 0;
    while (getBlock(aLocation,currentDepth) <> nil) do
        inc(currentDepth);
    dec(currentDepth); {go back to previous existing block}
    {split each block until we get to desired level}
    while (currentDepth <= aDepth-1) do begin
        getNode(aLocation,currentDepth).split;
        inc(currentDepth);
    end;
end;


end.
