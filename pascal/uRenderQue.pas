unit uRenderQue;

{*****************************************************
tRenderQue:

Handles rendering of fractal blocks
Feature:
    - Priority que
    - Symetric processing (for dual / quad processors)

******************************************************}

{todo: allow renderer to support customization.  I would like control over the
 following...
 what fratal type to use (madelbrot / julia)
 what color map to use
 how many itterations

 The percision will need to be autodetected.
 Probably the best thing to do here is just to pass in a fractal and just get
 the render to make a copy and tweak the percision a bit

 }

interface

uses
    math,
    uDebug,
    classes,
    uTime,
    uPage,
    uPageGLHW,
    uPageManager,
    uColors,
    uVector2d,
    uFractal,
    uOpenGL,
    uFractalHelper,
    sysUtils;

type
    {variois states opf a render block}
    tRenderStatus = (rsEMPTY,rsINQUE,rsRENDERING,rsRENDERED,rsUPLOADING,rsUPLOADED);
    {
     rsEMPTY: no rendered fractal data, page will be nil
     rsINQUE: block is in que to be rendered
     rsRENDERING: block is currently being rendered [renderPage allocated]
     rsRENDERED: block has been rendered but is not uploaded to a texture
     rsUPLOADING: block is currently being uploaded to video card   [renderPage.texture initilized]
     rsUPLOADED: block has been uploaded to video card and pages texture is active
    }

    {a section of the fractal}
    tRenderBlock = class
    PRIVATE
        {region to render}
        offset: tVector2d; {TODO: increase quality to 64bit}
        scale: extended;  {scale to render at [1..inf]}
    PROTECTED
        {render status}
        status: tRenderStatus;
    PUBLIC
        priority: integer;   {priority value.  Higher values will be rendered first}
        {if block contains all the same color then set to true (only valid when status = rsUPLOADED)}
        isTrivial: boolean;
        {page fractal is rendered to}

        texture: tGLTexture; {rendered texture data}

        procedure release;
        property getStatus : tRenderStatus read status;

        constructor create(aOffset: tVector2d;aScale: extended);
        destructor Destroy; override;
    end;

    {renders a single renderBlock, is passed data from tRenderQue}
    tRenderPipe = class
    PRIVATE
        pageManager: tPageManager;   {if assigned then blocks will use this pageManager to keep track of pages}
        currentBlock: tRenderBlock; {current block we are working on (could be nil)}
        fractal: tFractalMandelBrot; {fractal object used to render to block}
        renderPage: tPageGLHW;
    PUBLIC
        {assigns block as the current job of this render pipe.  If another job is
         currently being processed then the old job is droped}
        procedure assignJob(aRenderBlock: tRenderBlock);
        {returns render progress from [0..1]; 1 = finished or empty}
        function progress: single;

        procedure markAsRendered;
        procedure uploadToTexture;

        {returns true if pipe is empty}
        function empty: boolean;
        {todo: this is only here until threading is implemented}
        procedure continueRender;
        constructor create(aPageManager: tPageManager = nil);
        destructor Destroy; override;
    end;

    {prioritised texture upload que}

    {prioritised render que}
    tRenderQue = class
    PRIVATE
        pageManager: tPageManager;       {if assigned then blocks will use this pageManager to keep track of pages}
        jobList: TList;
        pipe: array[0..1] of tRenderPipe; {todo: do not hard wire the pipe count}
    PRIVATE
        function getJob(aIndex: integer): tRenderBlock;
    PUBLIC
        procedure applyRenderSettings(aColorMap: tColorMap);

        {adds a job to the joblist, will block duplicates}
        procedure addJob(aRenderBlock: tRenderBlock);
        {removes a job from the joblist (if present), and from the render pipes (if present)}
        procedure removeJob(aRenderBlock: tRenderBlock); overload;
        procedure removeJob(aRenderBlock: integer); overload;
        {refills any empty pipes with new blocks from the joblist}
        procedure refillPipes;
        {removes all jobs from cue (but not active pipes}
        procedure clearPending;
        procedure continueRender;
        function isCompleted: boolean; {returns true if all pipes are completed and no more jobs are left in the cue}
        constructor create(aPageManger: tPageManager = nil);
        destructor Destroy; override;
    end;

implementation

{----------------------------------------------------------}
{ tRenderBlock }
{----------------------------------------------------------}

{release memory for rendered data}
procedure tRenderBlock.release;
begin
    texture.free;
    texture := nil;
    status := rsEMPTY;
end;

constructor tRenderBlock.create(aOffset: tVector2d;aScale: extended);
begin
    texture := nil;
    status := rsEMPTY;
    offset := aOffset;
    scale := aScale;
    isTrivial := false;
end;

destructor tRenderBlock.Destroy;
begin
    {free rendered data}
    texture.free;
    inherited;
end;

{-------------------------------------------------------------------------}
{ tRenderPipe }
{-------------------------------------------------------------------------}

{assigns block as the current job of this render pipe.  If another job is
 currently being processed then the old job is droped}
{at this point we allocate memory to the renderBlocks renderPage, if the
 page already exists then we note a warning (because it means the block has
 probably already been rendered}
procedure tRenderPipe.assignJob(aRenderBlock: tRenderBlock);
begin
    {if a block was already being processed then just issue a warning and continue}
    if not Empty then warning(2,'Render pipe was assigned a new block when the previous had not finished');

    currentBlock := aRenderBlock;
    currentBlock.status := rsRENDERING;

    {if a previous page already exists then warn but continue}
    if assigned(currentBlock.texture) then warning(2,'Block already has a texture, overwritting');

    {setup fractal parameters}
    fractal.scale := currentBlock.scale;
    fractal.xOffset := currentBlock.offset.x;
    fractal.yOffset := currentBlock.offset.y;

    {decide on rendering percision}
    if true then begin
        {auto select render percision}
        fractal.renderPercision := vtFLT32;
        if (fractal.scale > 100000) then
            fractal.renderPercision := vtFLT64;
    end;
    fractal.updateRenderMethod;

    {and start the fractal rendering}
    fractal.startProgressiveRender;
end;

{todo: this is only here until threading is implemented}
procedure tRenderPipe.continueRender;
begin
    {nothing to do if the pipe is empty}
    if empty then exit;
    {otherwise render fractal a little more}
    if fractal.continueProgressiveRender(256) = 0 then begin
        {mark pipe as rendered}
        markAsRendered;
        {upload rendered data to blocks texture}
        uploadToTexture;
        {empty pipe}
        currentBlock := nil;
    end;
end;

{uploads rendered data to texture}
procedure tRenderPipe.uploadToTexture;
begin
    assert(assigned(currentBlock),'currentBlock=nil');
    {mark block as uploaded}
    currentBlock.status := rsUPLOADED;
    {upload it}
    currentBlock.texture.free;
    currentBlock.texture := tGltexture.create(gl,currentBlock.offset.print);
    currentBlock.texture.uploadFrom(renderPage,false);
    currentBlock.texture.setToClip;
end;


{mark pipe as rendered}
procedure tRenderPipe.markAsRendered;
begin
    {mark block as rendered}
    currentBlock.status := rsRENDERED;
    {if fractal is trivial (i.e. all same color) then record it in this renderBlock}
    currentBlock.isTrivial := fractal.isTrivial;
end;


{returns true if pipe is empty}
function tRenderPipe.empty: boolean;
begin
    result := (currentBlock = nil);
end;

{returns render progress from [0..1]; 1 = finished or empty}
function tRenderPipe.progress: single;
begin
    if empty then
        result := 1
    else
        result := fractal.progress;
end;

constructor tRenderPipe.create;
begin
    {allocate a blank fractal}
    pageManager := aPageManager;
    fractal := tFractalMandelBrot.create;
    fractal.renderSize := 64;

    {create page to render to}
    renderPage := tPageGLhw.create;
    renderPage.setPageSize(64,64,cfInt32,false);

    {set fractal to render to blocks page}
    fractal.assignRenderPage(renderPage);

    currentBlock := nil;
end;

destructor tRenderPipe.Destroy;
begin
    fractal.Free; {this leaves the fractals destionation page alone}
    renderPage.Free;
    inherited;
end;

{-------------------------------------------------------------------------}
{ tRenderQue }
{-------------------------------------------------------------------------}

{changes render settings of all que's}
procedure tRenderQue.applyRenderSettings(aColorMap: tColorMap);
var
    lp: integer;
begin
    for lp := low(pipe) to high(pipe) do begin
        pipe[lp].fractal.colorMap := aColorMap;
    end;

end;

procedure tRenderQue.addJob(aRenderBlock: tRenderBlock);
begin
    assert(assigned(aRenderBlock));
    {we block duplicate entries}
    if (jobList.IndexOf(aRenderBlock) <> -1) then exit;
    {add block to joblist}
    jobList.Add(aRenderBlock);
    {make job as in que}
    aRenderBlock.status := rsINQUE;
end;

procedure tRenderQue.removeJob(aRenderBlock: tRenderBlock);
var
    jobIndex: integer;
begin
    assert(assigned(aRenderBlock));
    {look for block in joblist and delete if found}
    jobIndex := jobList.IndexOf(aRenderBlock);
    if (jobINdex >= 0) then removeJob(jobIndex);
end;

{removes job by index}
procedure tRenderQue.removeJob(aRenderBlock: integer);
begin
    tRenderBlock(jobList[aRenderBlock]).status := rsEMPTY;
    jobList.Delete(aRenderBlock);
end;

{stub: only needed until threading is implemented}
procedure tRenderQue.clearPending;
begin
    {remove all jobs from job list}
    while (jobList.Count > 0) do removeJob(0);
end;

procedure tRenderQue.continueRender;
var
    lp: integer;
begin
    for lp := 0 to high(pipe) do pipe[lp].continueRender;
end;

constructor tRenderQue.create;
var
    lp: Integer;
begin
    pageManager := aPageManger;
    {create render pipes}
    for lp := 0 to high(pipe) do pipe[lp] := tRenderPipe.create(pageManager);
    {create joblist}
    jobList := TList.create;
end;

destructor tRenderQue.Destroy;
var
    lp: Integer;
begin
    {destroy joblist}
    jobList.free;
    {destroy render pipes}
    for lp := 0 to high(pipe) do pipe[lp].free;
    inherited;
end;

function tRenderQue.getJob(aIndex: integer): tRenderBlock;
begin
    result := jobList.items[aIndex];
end;

{returns true if all pipes are completed and no more jobs are left in the cue}
function tRenderQue.isCompleted: boolean;
var
    lp: integer;
begin
    result := false;
    {check if pipes are empty}
    for lp := 0 to high(pipe) do if not (pipe[lp].empty) then exit;
    {check if cue is empty}
    if (jobList.Count > 0) then exit;
    {ok ... we are complete}
    result := true;
    

end;

procedure tRenderQue.refillPipes;
var
    lp: integer;
    prioritySearch: integer;
    priorityHigh: integer;
    priorityFound: integer;
begin
    {no new jobs to allocate}
    if jobList.Count = 0 then exit;
    {look for any empty pipes}
    for lp := 0 to high(pipe) do if (jobList.Count <> 0) and (pipe[lp].empty) then begin
        note(5,'Adding job to render pipe');
        {find a job to fill the pipe}
        {look for highest priority}
        priorityHigh := 0;
        priorityFound := 0; {this defaults us to the first block if no blocks have a priority}
        for prioritySearch := 0 to jobList.Count - 1 do begin
            if getJob(prioritySearch).priority > priorityHigh then begin
                priorityHigh := getJob(prioritySearch).priority;
                priorityFound := prioritySearch;
            end;
        end;
        pipe[lp].assignJob(getJob(priorityFound));
        {remove that job from the que}
        jobList.Delete(priorityFound);
    end;
end;

end.
